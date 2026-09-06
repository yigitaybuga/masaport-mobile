import Foundation

/// `/venues/public/:venueId` içindeki zaman dilimi tanımı.
struct PublicSlot: Codable, Hashable, Identifiable {
    let id: Int
    let startTime: String
    let endTime: String?
    let durationMinutes: Int?
    let bookingMode: String?
    let requiresManualApproval: Bool?
    let bookingMessage: String?
    let minimumSpendRequired: Bool?
    let minimumSpendSummary: String?
    let prepaymentRequired: Bool?
    let prepaymentSummary: String?
    let prepaymentTotalAmount: APINumber?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMinutes = "duration_minutes"
        case bookingMode = "booking_mode"
        case requiresManualApproval = "requires_manual_approval"
        case bookingMessage = "booking_message"
        case minimumSpendRequired = "minimum_spend_required"
        case minimumSpendSummary = "minimum_spend_summary"
        case prepaymentRequired = "prepayment_required"
        case prepaymentSummary = "prepayment_summary"
        case prepaymentTotalAmount = "prepayment_total_amount"
    }

    var isRequestOnly: Bool { bookingMode == "REQUEST_ONLY" || requiresManualApproval == true }
}

struct SlotAvailability: Codable, Hashable {
    let isFull: Bool?
    let isBlocked: Bool?
    let isBlockedByTime: Bool?
    let availableGuestCapacity: Int?
    let availableTables: Int?

    enum CodingKeys: String, CodingKey {
        case isFull = "is_full"
        case isBlocked = "is_blocked"
        case isBlockedByTime = "is_blocked_by_time"
        case availableGuestCapacity = "available_guest_capacity"
        case availableTables = "available_tables"
    }

    var isBookable: Bool { isFull != true && isBlocked != true && isBlockedByTime != true }
}

struct DayAvailability: Codable, Hashable {
    let isBlocked: Bool?
    let isDayFull: Bool?
    let blockedReason: String?
    let slots: [String: SlotAvailability]?

    enum CodingKeys: String, CodingKey {
        case isBlocked = "is_blocked"
        case isDayFull = "is_day_full"
        case blockedReason = "blocked_reason"
        case slots
    }
}

struct VenueText: Codable, Hashable, Identifiable {
    let id: Int
    let title: String?
    let type: String?
    let content: String?
}

struct VenueAvailability: Codable {
    let id: Int
    let name: String?
    let timezone: String?
    let texts: [VenueText]?
    /// Haftanın günü → slotlar. Pazartesi = "1", Pazar = "7".
    let slots: [String: [PublicSlot]]?
    let blockedDates: [String]?
    let availability: [String: DayAvailability]?
    let isSubscriptionActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, timezone, texts, slots, availability, isSubscriptionActive
        case blockedDates = "blocked_dates"
    }

    var kvkkText: VenueText? { texts?.first { $0.type?.lowercased() == "kvkk" } }

    /// Belirli bir gün için slotlar ve o günün müsaitlik durumu.
    func slotOptions(for date: Date, calendar: Calendar = .istanbul) -> [SlotOption] {
        let weekday = calendar.component(.weekday, from: date) // 1 = Pazar
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let key = DateFormat.apiDay.string(from: date)
        let daySlots = slots?[String(isoWeekday)] ?? []
        let dayInfo = availability?[key]
        let blockedDay = blockedDates?.contains(key) == true || dayInfo?.isBlocked == true
        return daySlots.map { slot in
            let status = dayInfo?.slots?[String(slot.id)]
            let bookable = !blockedDay && (status?.isBookable ?? true)
            return SlotOption(slot: slot, status: status, isBookable: bookable, dayBlockedReason: blockedDay ? dayInfo?.blockedReason : nil)
        }
        .sorted { $0.slot.startTime < $1.slot.startTime }
    }
}

struct SlotOption: Hashable, Identifiable {
    let slot: PublicSlot
    let status: SlotAvailability?
    let isBookable: Bool
    let dayBlockedReason: String?

    var id: Int { slot.id }
}
