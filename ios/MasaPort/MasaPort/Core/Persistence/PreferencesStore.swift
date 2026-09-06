import Foundation
import Observation

/// Kalıcı kullanıcı tercihleri: seçili şehir ve hatırlanan misafir bilgileri.
@MainActor
@Observable
final class PreferencesStore {
    struct GuestProfile: Codable, Equatable {
        var name = ""
        var phone = ""
        var email = ""

        var isEmpty: Bool { name.isEmpty && phone.isEmpty && email.isEmpty }
    }

    private enum Key {
        static let city = "masaport.selectedCity"
        static let guest = "masaport.guestProfile"
        static let rememberGuest = "masaport.rememberGuest"
        static let recentSearches = "masaport.recentSearches"
        static let onboarded = "masaport.onboarded"
    }

    private let defaults: UserDefaults

    var selectedCity: CityRef? {
        didSet { save(selectedCity, key: Key.city) }
    }

    var guest: GuestProfile {
        didSet { if rememberGuest { save(guest, key: Key.guest) } }
    }

    var rememberGuest: Bool {
        didSet {
            defaults.set(rememberGuest, forKey: Key.rememberGuest)
            if rememberGuest { save(guest, key: Key.guest) } else { defaults.removeObject(forKey: Key.guest) }
        }
    }

    var recentSearches: [String] {
        didSet { defaults.set(recentSearches, forKey: Key.recentSearches) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarded) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedCity = Self.load(CityRef.self, key: Key.city, defaults: defaults)
        rememberGuest = defaults.object(forKey: Key.rememberGuest) as? Bool ?? true
        guest = Self.load(GuestProfile.self, key: Key.guest, defaults: defaults) ?? GuestProfile()
        recentSearches = defaults.stringArray(forKey: Key.recentSearches) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
    }

    func rememberSearch(_ term: String) {
        guard let term = term.nilIfBlank else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recentSearches.insert(term, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
    }

    func clearRecentSearches() {
        recentSearches = []
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
