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
    let startDate: Date
    let endDate: Date?
    let timeText: String
    let guestCount: Int
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

    var isUpcoming: Bool { (endDate ?? startDate.addingTimeInterval(3 * 3600)) >= .now }
    var isPending: Bool { status.uppercased() == "PENDING" }

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
