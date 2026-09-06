import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool?
    let data: Value?
    let error: String?
    let message: String?
    let code: String?
    let requestId: String?
}

struct APIError: LocalizedError, Equatable {
    let statusCode: Int
    let message: String
    let code: String?
    var detail: String? = nil

    var errorDescription: String? { message }
    var isNotFound: Bool { statusCode == 404 }
    var isRateLimited: Bool { statusCode == 429 }
    var isOffline: Bool { statusCode == 0 }

    static let offline = APIError(statusCode: 0, message: "Bağlantı kurulamadı. İnternet bağlantını kontrol edip tekrar dene.", code: "OFFLINE")
}

/// Sunucu Prisma `Decimal` alanlarını bazen string, bazen sayı olarak döndürür.
struct APINumber: Codable, Hashable {
    let value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Tüketici oturumu erişim token'ını sağlar; süresi dolduysa yeniler.
protocol AccessTokenProviding: AnyObject {
    func currentAccessToken() async -> String?
    /// 401 sonrası tek seferlik yenileme; başarısızsa oturum kapatılır ve nil döner.
    func refreshAccessToken() async -> String?
}

enum APIAuthMode {
    /// Anonim istek.
    case none
    /// Oturum varsa Bearer eklenir, yoksa anonim devam eder (public rezervasyon uçları).
    case optional
    /// Oturum zorunlu; token yoksa istek gönderilmeden hata döner.
    case required
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    let decoder: JSONDecoder
    private let encoder: JSONEncoder
    weak var tokenProvider: AccessTokenProviding?

    init(session: URLSession? = nil) {
        #if DEBUG
        self.session = session ?? (DemoMode.isEnabled ? DemoMode.makeSession() : Self.makeSession())
        #else
        self.session = session ?? Self.makeSession()
        #endif
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "MasaPort-iOS/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "1.0")"]
        return URLSession(configuration: configuration)
    }

    // MARK: Envelope'lu istekler

    func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = [], auth: APIAuthMode = .none) async throws -> Value {
        let (data, status) = try await perform(path, method: "GET", query: query, body: Optional<String>.none, auth: auth)
        return try decodeEnvelope(data, status: status)
    }

    func post<Value: Decodable, Body: Encodable>(_ path: String, body: Body, auth: APIAuthMode = .none) async throws -> Value {
        let (data, status) = try await perform(path, method: "POST", query: [], body: body, auth: auth)
        return try decodeEnvelope(data, status: status)
    }

    func patch<Value: Decodable, Body: Encodable>(_ path: String, body: Body, auth: APIAuthMode = .none) async throws -> Value {
        let (data, status) = try await perform(path, method: "PATCH", query: [], body: body, auth: auth)
        return try decodeEnvelope(data, status: status)
    }

    func delete<Value: Decodable, Body: Encodable>(_ path: String, body: Body?, auth: APIAuthMode = .none) async throws -> Value {
        let (data, status) = try await perform(path, method: "DELETE", query: [], body: body, auth: auth)
        return try decodeEnvelope(data, status: status)
    }

    /// Envelope kullanmayan uçlar (`/public/sectors` gibi çıplak diziler) veya `data: null` dönen
    /// ama `message` taşıyan cevaplar için ham çözümleme.
    func getRaw<Value: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Value {
        try await getRaw(path, query: query, method: "GET", body: Optional<String>.none)
    }

    func getRaw<Value: Decodable, Body: Encodable>(_ path: String, query: [URLQueryItem] = [], method: String, body: Body?, auth: APIAuthMode = .none) async throws -> Value {
        let (data, status) = try await perform(path, method: method, query: query, body: body, auth: auth)
        guard (200..<300).contains(status) else { throw Self.error(from: data, status: status, decoder: decoder) }
        return try decoder.decode(Value.self, from: data)
    }

    // MARK: Internals

    private func perform<Body: Encodable>(_ path: String, method: String, query: [URLQueryItem], body: Body?, auth: APIAuthMode = .none) async throws -> (Data, Int) {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        var token: String?
        if auth != .none {
            token = await tokenProvider?.currentAccessToken()
            if token == nil, auth == .required {
                throw APIError(statusCode: 401, message: "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED")
            }
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            var (data, response) = try await session.data(for: request)
            var status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Erişim token'ı süresi dolmuşsa bir kez yenileyip tekrar dene.
            if status == 401, token != nil, let renewed = await tokenProvider?.refreshAccessToken() {
                request.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
                (data, response) = try await session.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            }
            return (data, status)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut, .dnsLookupFailed:
                throw APIError.offline
            default:
                throw APIError(statusCode: 0, message: urlError.localizedDescription, code: "URL_ERROR")
            }
        }
    }

    private func decodeEnvelope<Value: Decodable>(_ data: Data, status: Int) throws -> Value {
        let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data)
        guard (200..<300).contains(status), envelope?.success != false, let value = envelope?.data else {
            throw Self.error(from: data, status: status, decoder: decoder, envelopeMessage: envelope?.error ?? envelope?.message, code: envelope?.code, detail: envelope?.message)
        }
        return value
    }

    private static func error(from data: Data, status: Int, decoder: JSONDecoder, envelopeMessage: String? = nil, code: String? = nil, detail: String? = nil) -> APIError {
        struct Loose: Decodable { let error: String?; let message: String?; let code: String? }
        let loose = try? decoder.decode(Loose.self, from: data)
        let message = envelopeMessage ?? loose?.error ?? loose?.message ?? Self.fallbackMessage(for: status)
        return APIError(statusCode: status, message: message, code: code ?? loose?.code, detail: detail ?? loose?.message)
    }

    private static func fallbackMessage(for status: Int) -> String {
        switch status {
        case 404: "Aradığın kayıt bulunamadı."
        case 429: "Çok fazla istek gönderildi. Biraz sonra tekrar dene."
        case 500...: "Sunucu şu anda yanıt veremiyor. Biraz sonra tekrar dene."
        default: HTTPURLResponse.localizedString(forStatusCode: status)
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: AppConfiguration.apiBaseURL.appending(path: normalizedPath), resolvingAgainstBaseURL: false) else {
            throw APIError(statusCode: 0, message: "Geçersiz API adresi", code: nil)
        }
        let items = query.filter { $0.value != nil && !($0.value ?? "").isEmpty }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            throw APIError(statusCode: 0, message: "Geçersiz API adresi", code: nil)
        }
        return url
    }
}
