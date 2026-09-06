import Foundation

enum AppConfiguration {
    static let apiBaseURL: URL = {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "MASAPORT_API_BASE_URL") as? String,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            preconditionFailure("MASAPORT_API_BASE_URL must be a valid URL.")
        }
        return url
    }()

    static func hostDeskWebSocketURL(venueID: Int) -> URL {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            preconditionFailure("MASAPORT_API_BASE_URL must be a valid URL.")
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/host-desk/ws"
        components.queryItems = [URLQueryItem(name: "venue_id", value: String(venueID))]
        guard let url = components.url else {
            preconditionFailure("Host Desk WebSocket URL could not be created.")
        }
        return url
    }
}
