import Foundation
import Observation

/// Uygulama içinden yapılan rezervasyonların yerel kaydı. Sunucuda tüketici hesabı ve
/// "rezervasyonlarım" ucu olmadığı için bu kayıt cihaza özeldir.
struct SavedReservation: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case restaurant, event }

    let id: UUID
    let kind: Kind
    let remoteId: Int?
    /// Check-in QR'ı ve takvim dosyası için sunucu UUID'si (restoran + etkinlik).
    var remoteUUID: String?
    let title: String
    let subtitle: String?
    let image: String?
    var startDate: Date
    var endDate: Date?
    var timeText: String
    var guestCount: Int
    var status: String
    let customerName: String
    let note: String?
    let venueId: Int?
    let listingSlug: String?
    let eventId: Int?
    let address: String?
    let phone: String?
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    // Sonradan eklenen alanlar: eski sürümlerin kaydettiği JSON'da yoktur, nil çözülür.
    /// İptal/değişiklik talebi için imzalı misafir bağlantısı (yalnızca restoran rezervasyonları).
    var managementURL: String? = nil
    var checkedIn: Bool? = nil

    var isUpcoming: Bool { (endDate ?? startDate.addingTimeInterval(3 * 3600)) >= .now }
    var isPending: Bool { status.uppercased() == "PENDING" }
    var isCancelled: Bool { status.uppercased() == "CANCELLED" }

    /// "Rezervasyonu yönet": gelecekteki, sonuçlanmamış ve giriş yapılmamış restoran rezervasyonlarında açılır.
    var managementLink: URL? {
        guard kind == .restaurant, isUpcoming, checkedIn != true,
              ["PENDING", "CONFIRMED"].contains(status.uppercased()),
              let raw = managementURL?.nilIfBlank,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// Bağlantının fragment'ında taşınan misafir token'ı (`#token=...`); durum yenilemede kullanılır.
    var managementToken: String? {
        guard let raw = managementURL?.nilIfBlank,
              let fragment = URLComponents(string: raw)?.percentEncodedFragment else { return nil }
        var components = URLComponents()
        components.percentEncodedQuery = fragment
        return components.queryItems?.first { $0.name == "token" }?.value?.nilIfBlank
    }

    /// Aynı sunucu kaydını gösteren iki kayıt (cihazdaki ve hesaptaki) eşleşir mi?
    func refersToSameBooking(as other: SavedReservation) -> Bool {
        guard kind == other.kind else { return false }
        if let lhs = remoteUUID?.lowercased(), let rhs = other.remoteUUID?.lowercased() { return lhs == rhs }
        if let lhs = remoteId, let rhs = other.remoteId { return lhs == rhs }
        return id == other.id
    }

    /// Misafir yönetim sayfasında yapılan iptal veya onaylanan değişikliği yerel kayda işler.
    func applying(_ managed: GuestManagedReservation) -> SavedReservation {
        var copy = self
        if let status = managed.status?.nilIfBlank { copy.status = status }
        if let guests = managed.guestCount, guests > 0 { copy.guestCount = guests }
        if let dayString = managed.reservationDate, let day = DateFormat.parseAPIDay(dayString),
           let start = managed.startTime?.nilIfBlank {
            copy.startDate = Self.combine(day: day, time: start)
            copy.endDate = managed.endTime?.nilIfBlank.map { Self.combine(day: day, time: $0) }
            copy.timeText = start.shortTime
        }
        // Sonuçlanan rezervasyonda bağlantı artık işe yaramaz.
        if !["PENDING", "CONFIRMED"].contains(copy.status.uppercased()) { copy.managementURL = nil }
        return copy
    }

    static func combine(day: Date, time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.istanbul.dateComponents([.year, .month, .day], from: day)
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.istanbul.date(from: components) ?? day
    }

    /// Girişte sözlü okunabilecek kısa kod: UUID'nin son 8 hanesi (check-in ucu bunu da kabul eder).
    static func shortCode(from uuid: String) -> String {
        String(uuid.replacingOccurrences(of: "-", with: "").suffix(8)).uppercased()
    }
}

@MainActor
@Observable
final class MyReservationsStore {
    private(set) var reservations: [SavedReservation] = []
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appending(path: "reservations.json")
        load()
    }

    var upcoming: [SavedReservation] { reservations.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate } }
    var past: [SavedReservation] { reservations.filter { !$0.isUpcoming }.sorted { $0.startDate > $1.startDate } }

    func add(_ reservation: SavedReservation) {
        reservations.removeAll { $0.id == reservation.id }
        reservations.append(reservation)
        persist()
    }

    func remove(_ reservation: SavedReservation) {
        reservations.removeAll { $0.id == reservation.id }
        persist()
    }

    /// Sunucudan gelen güncel durumu (iptal, bağlantı, tarih değişikliği) aynı rezervasyonun yerel kaydına yazar.
    func refresh(with latest: SavedReservation) {
        var changed = false
        for index in reservations.indices where reservations[index].refersToSameBooking(as: latest) {
            var local = reservations[index]
            local.status = latest.status
            local.startDate = latest.startDate
            local.endDate = latest.endDate
            local.timeText = latest.timeText
            local.guestCount = latest.guestCount
            local.managementURL = latest.managementURL
            local.checkedIn = latest.checkedIn ?? local.checkedIn
            if local.remoteUUID == nil { local.remoteUUID = latest.remoteUUID }
            if local != reservations[index] {
                reservations[index] = local
                changed = true
            }
        }
        if changed { persist() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedReservation].self, from: data) else { return }
        reservations = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(reservations)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Rezervasyonlar kaydedilemedi: \(error)")
        }
    }
}
