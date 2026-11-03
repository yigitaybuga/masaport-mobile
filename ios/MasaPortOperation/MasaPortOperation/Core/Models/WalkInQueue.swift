import Foundation

/// Kapı sırası kaydı (`GET /walk-in-queue/:venueId` → `active` / `recent`).
/// Sunucu alan adları camelCase'tir; istek gövdeleri snake_case'tir.
struct WalkInQueueEntry: Codable, Identifiable, Hashable {
    let id: Int
    var uuid: String? = nil
    let customerName: String
    var customerPhone: String? = nil
    var customerEmail: String? = nil
    let partySize: Int
    var quotedWaitMinutes: Int
    var note: String? = nil
    var status: String
    var position: Int? = nil
    var waitedMinutes: Int? = nil
    var notifiedAt: String? = nil
    var closedAt: String? = nil
    var reservationID: Int? = nil
    var createdAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, uuid, customerName, customerPhone, customerEmail, partySize, quotedWaitMinutes
        case note, status, position, waitedMinutes, notifiedAt, closedAt, createdAt
        case reservationID = "reservationId"
    }
}

extension WalkInQueueEntry {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        customerName = try container.decode(String.self, forKey: .customerName)
        partySize = try container.decode(Int.self, forKey: .partySize)
        status = try container.decode(String.self, forKey: .status)
        uuid = container.lenientString(forKey: .uuid)
        customerPhone = container.lenientString(forKey: .customerPhone)
        customerEmail = container.lenientString(forKey: .customerEmail)
        quotedWaitMinutes = container.lenientInt(forKey: .quotedWaitMinutes) ?? 0
        note = container.lenientString(forKey: .note)
        position = container.lenientInt(forKey: .position)
        waitedMinutes = container.lenientInt(forKey: .waitedMinutes)
        notifiedAt = container.lenientString(forKey: .notifiedAt)
        closedAt = container.lenientString(forKey: .closedAt)
        reservationID = container.lenientInt(forKey: .reservationID)
        createdAt = container.lenientString(forKey: .createdAt)
    }
}

struct WalkInQueueSnapshot: Codable {
    var active: [WalkInQueueEntry]
    var recent: [WalkInQueueEntry] = []
    var minutesPerParty: Int?
    var suggestedQuoteMinutes: Int?
}

/// WhatsApp / e-posta gönderim sonucu (`SENT`, `QUEUED`, `SKIPPED`, `FAILED`…).
struct WalkInQueueDelivery: Codable, Hashable {
    var status: String?
    var reason: String?

    var wasSent: Bool {
        ["SENT", "QUEUED", "DELIVERED", "ACCEPTED"].contains((status ?? "").uppercased())
    }
}

struct WalkInQueueCreateResult: Codable {
    let entry: WalkInQueueEntry
    var delivery: WalkInQueueDelivery?
}

struct WalkInQueueNotifyResult: Codable {
    let entry: WalkInQueueEntry
    var delivery: WalkInQueueDelivery?
    var emailDelivery: WalkInQueueDelivery?
}

struct WalkInQueueCreateRequest: Codable {
    let customerName: String
    let customerPhone: String?
    let customerEmail: String?
    let partySize: Int
    let quotedWaitMinutes: Int?
    let note: String?
    /// Telefon verildiyse misafire sırasını takip edeceği bağlantı gider.
    let sendLink: Bool

    enum CodingKeys: String, CodingKey {
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case customerEmail = "customer_email"
        case partySize = "party_size"
        case quotedWaitMinutes = "quoted_wait_minutes"
        case note
        case sendLink = "send_link"
    }
}

/// `POST /walk-in-queue/:venueId/:id/close`: LEFT (beklemeden ayrıldı) veya CANCELLED (sıradan çıkarıldı).
struct WalkInQueueCloseRequest: Codable {
    let status: String
}

// MARK: - Presentation

extension WalkInQueueEntry {
    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    var isNotified: Bool { status.uppercased() == "NOTIFIED" }
    var isActive: Bool { ["WAITING", "NOTIFIED"].contains(status.uppercased()) }
    var hasContactChannel: Bool { customerPhone != nil || customerEmail != nil }

    var joinedAt: Date? {
        guard let createdAt else { return nil }
        return Self.fractionalISOFormatter.date(from: createdAt) ?? Self.isoFormatter.date(from: createdAt)
    }

    /// Bekleme süresi istemcide her dakika yeniden hesaplanır; liste yeniden çekilmese de sayaç donmaz.
    func waitedMinutes(at referenceDate: Date) -> Int {
        guard let joinedAt else { return waitedMinutes ?? 0 }
        return max(0, Int((referenceDate.timeIntervalSince(joinedAt) / 60).rounded()))
    }

    func isOverdue(at referenceDate: Date) -> Bool {
        isActive && waitedMinutes(at: referenceDate) > quotedWaitMinutes
    }

    func waitText(at referenceDate: Date) -> String {
        let waited = waitedMinutes(at: referenceDate)
        return isOverdue(at: referenceDate)
            ? "\(waited) / \(quotedWaitMinutes) dk · süre aşıldı"
            : "\(waited) / \(quotedWaitMinutes) dk bekliyor"
    }

    var partyText: String { "\(partySize) kişi" }

    var phoneURL: URL? {
        let normalized = (customerPhone ?? "").filter { $0.isNumber || $0 == "+" }
        return normalized.isEmpty ? nil : URL(string: "tel:\(normalized)")
    }

    /// "Oturt": walk-in formu ön dolu açılır, kayıt oluşunca sunucu sırayı aynı işlemde kapatır.
    var walkInPrefill: WalkInPrefill {
        WalkInPrefill(
            customerName: customerName,
            customerPhone: customerPhone ?? "",
            guestCount: partySize,
            note: note,
            sourceTitle: customerPhone == nil
                ? "Kapı sırasından oturtuluyor. Masa açmak için telefon gerekir; telefonu yoksa sıradan \u{201C}Masa açmadan oturtuldu\u{201D} seçin."
                : "Kapı sırasından oturtuluyor: kayıt oluşturulunca sıra kaydı otomatik kapanır.",
            queueEntryID: id
        )
    }
}

enum WalkInQueueMessage {
    /// Sıraya ekleme sonucu (web paneliyle aynı dil).
    static func added(_ result: WalkInQueueCreateResult) -> String {
        var parts = ["\(result.entry.customerName) sıraya eklendi\(result.entry.position.map { " (\($0). sıra)" } ?? "")."]
        if let delivery = result.delivery {
            parts.append(delivery.wasSent
                ? "Sıra bağlantısı misafire gönderildi."
                : "Bağlantı gönderilmedi\(delivery.reason.map { ": \($0)" } ?? ".")")
        }
        return parts.joined(separator: " ")
    }

    /// "Masa hazır" sonucu: hangi kanaldan gittiği; hiçbiri gitmediyse yalnızca misafirin verdiği kanalların nedeni.
    static func ready(_ result: WalkInQueueNotifyResult, entry: WalkInQueueEntry) -> String {
        let channels = [
            result.delivery?.wasSent == true ? "WhatsApp" : nil,
            result.emailDelivery?.wasSent == true ? "e-posta" : nil
        ].compactMap { $0 }
        if !channels.isEmpty {
            return "\(entry.customerName) için \u{201C}masanız hazır\u{201D} mesajı \(channels.joined(separator: " ve ")) ile gönderildi."
        }
        let reasons = [
            entry.customerPhone != nil ? result.delivery?.reason : nil,
            entry.customerEmail != nil ? result.emailDelivery?.reason : nil
        ].compactMap { $0 }
        let base = "\(entry.customerName) haberdar edildi olarak işaretlendi."
        return reasons.isEmpty ? "\(base) Misafire sözlü olarak haber verin." : "\(base) Mesaj gönderilmedi: \(reasons.joined(separator: " "))"
    }
}
