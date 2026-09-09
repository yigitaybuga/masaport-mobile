import Foundation

enum WaitlistFilter: String, CaseIterable, Identifiable {
    case all, waiting, offered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .waiting: "Bekleyen"
        case .offered: "Teklif"
        }
    }

    func count(in entries: [WaitlistEntry]) -> Int {
        switch self {
        case .all: entries.count
        case .waiting: entries.count { $0.status == "WAITING" }
        case .offered: entries.count { $0.status == "OFFERED" }
        }
    }
}

struct WaitlistActionCandidate {
    enum Kind: Equatable { case offer, cancel }

    let entry: WaitlistEntry
    let kind: Kind

    var title: String {
        kind == .offer ? "Masa teklifi gönderilsin mi?" : "Bekleme kaydı kaldırılsın mı?"
    }

    var confirmationTitle: String {
        kind == .offer ? "Teklif gönder" : "Listeden kaldır"
    }

    var message: String {
        switch kind {
        case .offer:
            "\(entry.customerName) için uygun masa tutulacak ve misafire kabul bağlantısı gönderilecek."
        case .cancel:
            "\(entry.customerName) aktif bekleme listesinden kaldırılacak."
        }
    }
}

extension WaitlistEntry {
    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let ISOFormatter = ISO8601DateFormatter()

    var shortTime: String {
        timeSlot.map { String($0.startTime.prefix(5)) } ?? "—"
    }

    var shortDate: String {
        guard let date = Self.apiDateFormatter.date(from: reservationDate) else {
            return String(reservationDate.suffix(5))
        }
        return Self.shortDateFormatter.string(from: date)
    }

    var phoneURL: URL? {
        let normalized = customerPhone.filter { $0.isNumber || $0 == "+" }
        return normalized.isEmpty ? nil : URL(string: "tel:\(normalized)")
    }

    var waitingText: String {
        guard let created = Self.parseISODate(createdAt) else { return "aktif bekleme" }
        let minutes = max(0, Int(Date.now.timeIntervalSince(created) / 60))
        if minutes < 60 { return "\(minutes) dk bekliyor" }
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            return "\(days) gündür bekliyor"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) sa bekliyor" : "\(hours) sa \(remainder) dk bekliyor"
    }

    var offerExpiryText: String? {
        guard let expiry = Self.parseISODate(offerExpiresAt) else { return nil }
        let minutes = Int(expiry.timeIntervalSince(Date.now) / 60)
        if minutes <= 0 { return "Teklif süresi doldu" }
        return "\(minutes) dk kaldı"
    }

    var offerHasExpired: Bool {
        guard let expiry = Self.parseISODate(offerExpiresAt) else { return false }
        return expiry <= .now
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalISOFormatter.date(from: value) ?? ISOFormatter.date(from: value)
    }
}

extension WaitlistEntry {
    /// Bekleme kaydını walk-in formuna taşır.
    var walkInPrefill: WalkInPrefill {
        WalkInPrefill(
            customerName: customerName,
            customerPhone: customerPhone,
            guestCount: guestCount,
            note: note,
            sourceTitle: "Bekleme listesinden dönüştürülüyor: kayıt oluşturulunca bekleme kaydı otomatik kapatılır."
        )
    }
}
