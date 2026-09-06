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

    private var socketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var venueID: Int?
    private var accessToken: String?
    private var latestVersion = 0

    func connect(venueID: Int, accessToken: String) {
        guard !accessToken.isEmpty else {
            disconnect()
            return
        }

        self.venueID = venueID
        self.accessToken = accessToken
        #if DEBUG
        if DemoMode.isEnabled {
            state = .connected
            return
        }
        #endif
        reconnectTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        latestVersion = 0
        openSocket()
    }

    func disconnect() {
        venueID = nil
        accessToken = nil
        latestVersion = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        state = .disconnected
    }

    private func openSocket() {
        guard let venueID, let accessToken else {
            state = .disconnected
            return
        }

        var request = URLRequest(url: AppConfiguration.hostDeskWebSocketURL(venueID: venueID))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socketTask = task
        state = .connecting
        task.resume()
        receiveNext(from: task)
    }

    private func receiveNext(from task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.socketTask === task else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveNext(from: task)
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
            return
        }
        if event.type == "error" {
            scheduleReconnect()
            return
        }
        guard event.type == "host_desk_changed", let version = event.version, version > latestVersion else { return }
        latestVersion = version
        onChange?(event)
    }

    private func scheduleReconnect() {
        guard venueID != nil, accessToken != nil else {
            state = .disconnected
            return
        }
        state = .disconnected
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.openSocket()
        }
    }
}
