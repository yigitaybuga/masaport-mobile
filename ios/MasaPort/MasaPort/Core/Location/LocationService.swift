import CoreLocation
import Foundation
import Observation

/// Yalnızca "kullanırken" izniyle tek seferlik konum alır; arka plan takibi yapılmaz.
@MainActor
@Observable
final class LocationService {
    enum State: Equatable {
        case idle
        case requesting
        case located(latitude: Double, longitude: Double)
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    private let manager = CLLocationManager()

    var coordinate: (latitude: Double, longitude: Double)? {
        if case let .located(latitude, longitude) = state { return (latitude, longitude) }
        return nil
    }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// İzin daha önce verilmişse sessizce konum alır; verilmemişse sistem izni ister.
    func locate() async {
        if isDenied {
            state = .denied
            return
        }
        state = .requesting
        do {
            for try await update in CLLocationUpdate.liveUpdates(.default) {
                if update.authorizationDenied || update.authorizationRestricted {
                    state = .denied
                    return
                }
                if update.locationUnavailable {
                    state = .unavailable
                    return
                }
                if let location = update.location {
                    state = .located(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    return
                }
            }
            if state == .requesting { state = .unavailable }
        } catch {
            state = .unavailable
        }
    }
}
