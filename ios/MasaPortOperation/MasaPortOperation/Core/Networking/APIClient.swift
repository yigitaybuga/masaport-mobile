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
    /// `/mobile/auth/refresh` geçersiz, iptal edilmiş veya süresi dolmuş refresh token için 401 döner;
    /// 403 de kalıcı yetki kaybıdır. 429/5xx ve ağ hataları geçicidir, oturumu kapatmaz.
    var rejectsSession: Bool { statusCode == 401 || statusCode == 403 }
    var isConflict: Bool { statusCode == 409 || code == "RESOURCE_CONFLICT" }
}

/// Erişim token'ı yenileme denemesinin sonucu.
enum TokenRefreshOutcome: Equatable {
    /// Sunucu yeni bir erişim token'ı verdi.
    case refreshed(accessToken: String)
    /// Sunucu refresh token'ı reddetti (iptal, süre dolumu, yetki kaybı); yerel oturum kapatılır.
    case rejected
    /// Ağ veya geçici sunucu hatası; oturum korunur, daha sonra yeniden denenir.
    case unavailable
}

final class APIClient: @unchecked Sendable {
    typealias RefreshHandler = @Sendable () async -> TokenRefreshOutcome

    static let shared = APIClient()

    /// Kimlik doğrulama uçları erişim token'ı taşımaz; 401 aldıklarında token yenilenmez ve tekrar denenmez.
    private static let authenticationPaths: Set<String> = [
        "mobile/auth/login",
        "mobile/auth/refresh",
        "mobile/auth/logout"
    ]

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    /// Token durumu hem ana aktörden hem de ağ görevlerinden okunur; erişim kilitle sıralanır.
    private let lock = NSLock()
    private var accessToken: String?
    private var refreshHandler: RefreshHandler?
    private var inFlightRefresh: Task<TokenRefreshOutcome, Never>?

    init(session: URLSession? = nil) {
        #if DEBUG
        self.session = session ?? (DemoMode.isEnabled ? DemoMode.makeSession() : .shared)
        #else
        self.session = session ?? .shared
        #endif
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    var currentAccessToken: String? {
        lock.withLock { accessToken }
    }

    func setAccessToken(_ token: String?) {
        lock.withLock { accessToken = token }
    }

    /// Oturum sahibi (SessionStore) refresh token'ı saklar; istemci yalnızca ne zaman yenileneceğini bilir.
    func setRefreshHandler(_ handler: RefreshHandler?) {
        lock.withLock { refreshHandler = handler }
    }

    /// Erişim token'ını tek uçuşta yeniler: eşzamanlı 401'ler aynı isteği bekler.
    /// `rejectedToken` reddedilen token'dır; o arada token zaten değiştiyse ağ isteği yapılmaz.
    func refreshAccessToken(rejecting rejectedToken: String? = nil) async -> TokenRefreshOutcome {
        enum Step {
            case finished(TokenRefreshOutcome)
            case join(Task<TokenRefreshOutcome, Never>)
        }
        let step: Step = lock.withLock {
            if let rejectedToken, let current = accessToken, current != rejectedToken {
                return .finished(.refreshed(accessToken: current))
            }
            if let inFlightRefresh {
                return .join(inFlightRefresh)
            }
            guard let refreshHandler else { return .finished(.rejected) }
            let task = Task { await refreshHandler() }
            inFlightRefresh = task
            return .join(task)
        }

        let task: Task<TokenRefreshOutcome, Never>
        switch step {
        case .finished(let outcome):
            return outcome
        case .join(let pending):
            task = pending
        }
        let outcome = await task.value
        lock.withLock {
            if inFlightRefresh == task { inFlightRefresh = nil }
            if case .refreshed(let token) = outcome { accessToken = token }
        }
        return outcome
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
        let bodyData = try body.map { try encoder.encode($0) }
        guard !Self.isAuthenticationPath(path) else {
            let (data, statusCode) = try await send(url: url, method: method, body: bodyData, accessToken: nil)
            return try decode(data, statusCode: statusCode)
        }

        // Süren bir yenileme varsa eski token'la kesin 401 almak yerine onu bekle.
        await waitForInFlightRefresh()
        let sentToken = currentAccessToken
        var (data, statusCode) = try await send(url: url, method: method, body: bodyData, accessToken: sentToken)

        // 401 kimlik doğrulama katmanından döner; istek işlenmemiştir, yeni token'la bir kez tekrarlanabilir.
        if statusCode == 401, case .refreshed(let newToken) = await refreshAccessToken(rejecting: sentToken) {
            try Task.checkCancellation()
            (data, statusCode) = try await send(url: url, method: method, body: bodyData, accessToken: newToken)
        }
        return try decode(data, statusCode: statusCode)
    }

    private func send(url: URL, method: String, body: Data?, accessToken: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func decode<Value: Decodable>(_ data: Data, statusCode: Int) throws -> Value {
        let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data)

        guard (200..<300).contains(statusCode), envelope?.success == true else {
            let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw APIError(
                statusCode: statusCode,
                message: envelope?.error ?? envelope?.message ?? fallback,
                code: envelope?.code,
                requestId: envelope?.requestId,
                detail: envelope?.message
            )
        }
        if let value = envelope?.data {
            return value
        }
        // Bazı uçlar yalnızca `{ success, message }` döner; boş yanıt bekleyen çağrılar için geçerli sayılır.
        if let empty = EmptyResponse() as? Value {
            return empty
        }
        throw APIError(statusCode: statusCode, message: "Sunucu beklenen veriyi döndürmedi.", code: nil, requestId: envelope?.requestId)
    }

    private func waitForInFlightRefresh() async {
        guard let task = lock.withLock({ inFlightRefresh }) else { return }
        _ = await task.value
    }

    private static func isAuthenticationPath(_ path: String) -> Bool {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathOnly = normalized.split(separator: "?", maxSplits: 1).first.map(String.init) ?? normalized
        return authenticationPaths.contains(pathOnly)
    }

    private func makeURL(path: String) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: normalizedPath, relativeTo: AppConfiguration.apiBaseURL.appendingPathComponent(""))?.absoluteURL else {
            throw APIError(statusCode: 0, message: "Geçersiz API adresi", code: nil, requestId: nil)
        }
        return url
    }
}

extension Error {
    /// Görev iptali (ör. yenileme sırasında ekrandan ayrılma) kullanıcıya hata olarak gösterilmez.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
