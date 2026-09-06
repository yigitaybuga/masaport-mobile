import Foundation

/// Check-in uçları yanıtı iki kat sarar: dış zarfın `data` alanı yine `{ success, data, error, message }` biçimindedir.
struct CheckinPayload<Value: Codable>: Codable {
    let success: Bool
    let data: Value?
    let error: String?
    let message: String?
}

struct CheckinStatus: Codable, Equatable {
    let type: String
    let id: Int
    let uuid: String
    let venue: String
    let guestCount: Int
    let status: String?
    let paymentStatus: String?
    let checkedIn: Bool?
    let checkedInAt: String?
    let reservationDate: String?
    let startTime: String?
    let tables: [String]?
    let eventTitle: String?
    let customerName: String?
    let customerPhone: String?
    let contactName: String?
    let eventStartTime: String?
    let canCheckIn: Bool?
    let checkInWarning: String?
    let minutesUntilReservation: Int?

    var isEvent: Bool { type.lowercased() == "event" }
    var isCheckedIn: Bool { checkedIn ?? false }
    var displayName: String {
        let name = isEvent ? (contactName ?? "") : (customerName ?? "")
        return name.isEmpty ? "Misafir" : name
    }
    var isPaid: Bool { (paymentStatus ?? "").uppercased() == "PAID" }
    var needsEarlyConfirmation: Bool { canCheckIn == false && checkInWarning != nil }
}

struct CheckinResult: Codable, Equatable {
    let id: Int
    let uuid: String
    let venue: String
    let guestCount: Int
    let customerName: String?
    let contactName: String?
    let eventTitle: String?
    let tables: [String]?
    let checkedInAt: String?

    var displayName: String {
        let name = (contactName ?? customerName) ?? ""
        return name.isEmpty ? "Misafir" : name
    }
}

struct RestaurantCheckinRequest: Codable {
    let forceCheckIn: Bool?
    let expectedUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case forceCheckIn
        case expectedUpdatedAt = "expected_updated_at"
    }
}

enum CheckinIdentifier {
    private static let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#

    /// QR içeriğini (düz UUID, UUID ile biten URL, JSON içinde uuid) veya 8 karakterli kısa kodu çözer.
    static func normalize(_ rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uuid = object["uuid"] as? String {
            return normalize(uuid)
        }

        if let range = trimmed.range(of: uuidPattern, options: .regularExpression) {
            return String(trimmed[range]).lowercased()
        }

        let candidate = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        if candidate.count == 8, candidate.allSatisfy(\.isHexDigit) {
            return candidate.lowercased()
        }
        #if DEBUG
        if DemoMode.isEnabled, candidate.count == 8 { return candidate.lowercased() }
        #endif
        return nil
    }
}

extension APIError {
    var isEarlyCheckInWarning: Bool {
        message == "EARLY_CHECKIN_WARNING" || code == "EARLY_CHECKIN_WARNING"
    }
}
