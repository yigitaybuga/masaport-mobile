import Foundation

struct HostDeskChange: Decodable, Equatable {
    let type: String
    let venueID: Int?
    let resources: [String]?
    let version: Int?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case type, resources, version, code
        case venueID = "venueId"
    }
}

@MainActor
final class HostDeskLiveUpdates: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: ConnectionState = .disconnected
    var onChange: ((HostDeskChange) -> Void)?
    /// Kopan bağlantı yeniden kurulduğunda çağrılır; aradaki değişiklikler kaçmış olabilir, veri yeniden yüklenmeli.
    var onResync: (() -> Void)?

    private let api: APIClient
    private var socketTask: URLSessionWebSocketTask?
    /// Açık soketin kimlik doğrulamasında kullanılan token; sunucu reddederse yenileme buna göre yapılır.
    private var socketToken: String?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var venueID: Int?
    private var latestVersion = 0
    /// Bu `connect` çağrısından beri en az bir kez `ready` alındıysa sonraki `ready` bir yeniden bağlanmadır.
    private var hasBeenReady = false
    private var reconnectAttempts = 0
    /// Ardışık kimlik hatalarında token yalnızca bir kez yenilenir; döngüye girip refresh token tüketilmez.
    private var canRefreshForAuthError = true

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Yeni bir bağlantı kurar. Çağıran veriyi hemen önce (veya aynı anda) yüklediği için ilk `ready`
    /// yeniden yükleme tetiklemez; ön plana dönüşte taze bir soket için de bu kullanılır.
    func connect(venueID: Int) {
        self.venueID = venueID
        #if DEBUG
        if DemoMode.isEnabled {
            state = .connected
            return
        }
        #endif
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
        latestVersion = 0
        hasBeenReady = false
        reconnectAttempts = 0
        canRefreshForAuthError = true
        openSocket()
    }

    func disconnect() {
        venueID = nil
        latestVersion = 0
        hasBeenReady = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
        state = .disconnected
    }

    private func openSocket() {
        guard let venueID, let accessToken = api.currentAccessToken, !accessToken.isEmpty else {
            state = .disconnected
            return
        }

        var request = URLRequest(url: AppConfiguration.hostDeskWebSocketURL(venueID: venueID))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socketTask = task
        socketToken = accessToken
        state = .connecting
        task.resume()
        receiveNext(from: task)
    }

    private func closeSocket() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
    }

    private func receiveNext(from task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.socketTask === task else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    if self.socketTask === task { self.receiveNext(from: task) }
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let value):
            data = Data(value.utf8)
        case .data(let value):
            data = value
        @unknown default:
            return
        }

        guard let event = try? JSONDecoder().decode(HostDeskChange.self, from: data) else { return }
        if event.type == "ready" {
            latestVersion = event.version ?? 0
            state = .connected
            reconnectAttempts = 0
            canRefreshForAuthError = true
            startHeartbeat()
            if hasBeenReady {
                onResync?()
            }
            hasBeenReady = true
            return
        }
        if event.type == "error" {
            // Sunucu hata çerçevesinin ardından soketi kapatır; o kapanış ayrıca yeniden bağlanma tetiklemesin.
            let rejectedToken = socketToken
            closeSocket()
            if event.code == "UNAUTHENTICATED", canRefreshForAuthError {
                reauthenticate(rejecting: rejectedToken)
            } else {
                scheduleReconnect()
            }
            return
        }
        guard event.type == "host_desk_changed", let version = event.version, version > latestVersion else { return }
        latestVersion = version
        onChange?(event)
    }

    /// Süresi dolan erişim token'ını ortak yenileme yolundan tazeler ve yeni token'la hemen bağlanır.
    private func reauthenticate(rejecting rejectedToken: String?) {
        canRefreshForAuthError = false
        state = .connecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, api] in
            let outcome = await api.refreshAccessToken(rejecting: rejectedToken)
            guard !Task.isCancelled, let self, self.venueID != nil else { return }
            switch outcome {
            case .refreshed:
                self.openSocket()
            case .rejected:
                // Oturum kapatıldı; ekran giriş görünümüne geçerken bağlantı kurulmaz.
                self.state = .disconnected
            case .unavailable:
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        closeSocket()
        guard venueID != nil else {
            state = .disconnected
            return
        }
        state = .disconnected
        reconnectAttempts += 1
        // 2, 4, 8, 16, 30 sn: sunucu kapalıyken her 2 sn'de bir el sıkışma denenmez.
        let delay = min(30, 1 << min(reconnectAttempts, 5))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openSocket()
        }
    }

    /// Arka plandan dönüşte veya ağ değişiminde yarı açık kalan soketi fark etmek için protokol düzeyinde ping.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        guard let task = socketTask else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                let isAlive = await Self.ping(task)
                guard !Task.isCancelled, let self, self.socketTask === task else { return }
                if !isAlive {
                    self.scheduleReconnect()
                    return
                }
            }
        }
    }

    /// Pong 10 sn içinde gelmezse bağlantı ölü kabul edilir.
    private nonisolated static func ping(_ task: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = PingGate(continuation)
            task.sendPing { error in gate.resume(error == nil) }
            Task {
                try? await Task.sleep(for: .seconds(10))
                gate.resume(false)
            }
        }
    }
}

/// Ping yanıtı ile zaman aşımından hangisi önce gelirse devamı yalnızca bir kez sürdürür.
private final class PingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
