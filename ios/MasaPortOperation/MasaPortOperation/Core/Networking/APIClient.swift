import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let data: Value?
    let error: String?
    let message: String?
    let code: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case success, data, error, message, code
        case requestId = "requestId"
    }
}

struct APIError: LocalizedError, Equatable {
    let statusCode: Int
    let message: String
    let code: String?
    let requestId: String?
    /// Sunucunun `message` alanı; `error` alanı makine kodu olduğunda insan için açıklama burada gelir.
    var detail: String? = nil

    var errorDescription: String? { message }

    var isUnauthorized: Bool { statusCode == 401 }
    var isConflict: Bool { statusCode == 409 || code == "RESOURCE_CONFLICT" }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var accessToken: String?

    init(session: URLSession? = nil) {
        #if DEBUG
        self.session = session ?? (DemoMode.isEnabled ? DemoMode.makeSession() : .shared)
        #else
        self.session = session ?? .shared
        #endif
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func get<Value: Decodable>(_ path: String) async throws -> Value {
        try await request(path, method: "GET", body: Optional<String>.none)
    }

    func post<Value: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Value {
        try await request(path, method: "POST", body: body)
    }

    func post<Value: Decodable>(_ path: String) async throws -> Value {
        try await request(path, method: "POST", body: Optional<String>.none)
    }

    func put<Value: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Value {
        try await request(path, method: "PUT", body: body)
    }

    private func request<Value: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        body: Body?
    ) async throws -> Value {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data)

        guard (200..<300).contains(statusCode), envelope?.success == true, let value = envelope?.data else {
            let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw APIError(
                statusCode: statusCode,
                message: envelope?.error ?? envelope?.message ?? fallback,
                code: envelope?.code,
                requestId: envelope?.requestId,
                detail: envelope?.message
            )
        }
        return value
    }

    private func makeURL(path: String) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: normalizedPath, relativeTo: AppConfiguration.apiBaseURL.appendingPathComponent(""))?.absoluteURL else {
            throw APIError(statusCode: 0, message: "Geçersiz API adresi", code: nil, requestId: nil)
        }
        return url
    }
}
