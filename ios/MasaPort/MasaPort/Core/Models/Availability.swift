import Foundation

/// `/venues/public/:venueId` içindeki zaman dilimi tanımı (haftalık şablon).
/// Belirli bir tarihte geçerli kural `availability[tarih].slots[id]` içinde gelir ve şablonu ezer; bkz. `applying(_:)`.
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
    // Sonradan eklenen alanlar; eski API cevaplarında bulunmayabilir.
    var minimumSpendAmount: APINumber? = nil
    var prepaymentMode: String? = nil
    var prepaymentAmount: APINumber? = nil
    /// `PREAUTH`: tutar kartta bloke edilir, çekilmez (kart provizyonu). `CHARGE`: ön ödeme tahsil edilir.
    var prepaymentCaptureMode: String? = nil
    var minimumDurationMinutes: Int? = nil

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
        case minimumSpendAmount = "minimum_spend_amount"
        case prepaymentMode = "prepayment_mode"
        case prepaymentAmount = "prepayment_amount"
        case prepaymentCaptureMode = "prepayment_capture_mode"
        case minimumDurationMinutes = "minimum_duration_minutes"
    }

    var isRequestOnly: Bool { bookingMode == "REQUEST_ONLY" || requiresManualApproval == true }
    var requiresPrepayment: Bool { prepaymentRequired == true }
    var isPreauth: Bool { requiresPrepayment && prepaymentCaptureMode?.uppercased() == "PREAUTH" }

    /// Kişi sayısına göre sunucuda hesaplanmış ön ödeme/provizyon toplamı.
    var prepaymentTotal: Double? {
        guard let value = prepaymentTotalAmount?.value, value > 0 else { return nil }
        return value
    }

    var prepaymentTitle: String { isPreauth ? "Kart provizyonu" : "Ön ödeme" }

    /// Web'deki ödeme adımıyla aynı açıklama: provizyonda tutar çekilmez, kartta bloke edilir.
    var prepaymentExplanation: String {
        isPreauth
            ? "Tutar kartından çekilmez; rezervasyon teminatı olarak geçici bloke edilir. Geldiğinde bloke kaldırılır, gelmemen ya da geç iptal etmen durumunda işletme bu tutarı tahsil edebilir. Provizyon için kredi kartı gerekir."
            : "Ödeme güvenli ödeme sayfasında tamamlanır."
    }

    /// O tarihte geçerli kuralı (etkinlik gecesi, özel kural, provizyon, onay) şablonun üstüne uygular.
    /// Sunucu kuralı göndermediyse (eski API) şablon olduğu gibi kalır.
    func applying(_ rule: SlotAvailability?) -> PublicSlot {
        guard let rule, rule.carriesRule else { return self }
        return PublicSlot(
            id: id,
            startTime: rule.startTime?.nilIfBlank ?? startTime,
            endTime: rule.endTime?.nilIfBlank ?? endTime,
            durationMinutes: rule.durationMinutes ?? durationMinutes,
            bookingMode: rule.bookingMode,
            requiresManualApproval: rule.requiresManualApproval,
            bookingMessage: rule.bookingMessage,
            minimumSpendRequired: rule.minimumSpendRequired,
            minimumSpendSummary: rule.minimumSpendSummary,
            prepaymentRequired: rule.prepaymentRequired,
            prepaymentSummary: rule.prepaymentSummary,
            prepaymentTotalAmount: rule.prepaymentTotalAmount,
            minimumSpendAmount: rule.minimumSpendAmount,
            prepaymentMode: rule.prepaymentMode,
            prepaymentAmount: rule.prepaymentAmount,
            prepaymentCaptureMode: rule.prepaymentCaptureMode,
            minimumDurationMinutes: rule.minimumDurationMinutes ?? minimumDurationMinutes
        )
    }
}

/// `availability[tarih].slots[id]`: o tarihin doluluk durumu ve o tarihte geçerli rezervasyon kuralı.
struct SlotAvailability: Codable, Hashable {
    let isFull: Bool?
    let isBlocked: Bool?
    let isBlockedByTime: Bool?
    let availableGuestCapacity: Int?
    let availableTables: Int?
    // Tarihe özel kural; haftalık şablondaki aynı alanlardan önceliklidir.
    var startTime: String? = nil
    var endTime: String? = nil
    var durationMinutes: Int? = nil
    var bookingMode: String? = nil
    var requiresManualApproval: Bool? = nil
    var bookingMessage: String? = nil
    var minimumSpendRequired: Bool? = nil
    var minimumSpendAmount: APINumber? = nil
    var minimumSpendSummary: String? = nil
    var prepaymentRequired: Bool? = nil
    var prepaymentMode: String? = nil
    var prepaymentAmount: APINumber? = nil
    var prepaymentTotalAmount: APINumber? = nil
    var prepaymentSummary: String? = nil
    var prepaymentCaptureMode: String? = nil
    var minimumDurationMinutes: Int? = nil
    var effectiveRuleName: String? = nil

    enum CodingKeys: String, CodingKey {
        case isFull = "is_full"
        case isBlocked = "is_blocked"
        case isBlockedByTime = "is_blocked_by_time"
        case availableGuestCapacity = "available_guest_capacity"
        case availableTables = "available_tables"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMinutes = "duration_minutes"
        case bookingMode = "booking_mode"
        case requiresManualApproval = "requires_manual_approval"
        case bookingMessage = "booking_message"
        case minimumSpendRequired = "minimum_spend_required"
        case minimumSpendAmount = "minimum_spend_amount"
        case minimumSpendSummary = "minimum_spend_summary"
        case prepaymentRequired = "prepayment_required"
        case prepaymentMode = "prepayment_mode"
        case prepaymentAmount = "prepayment_amount"
        case prepaymentTotalAmount = "prepayment_total_amount"
        case prepaymentSummary = "prepayment_summary"
        case prepaymentCaptureMode = "prepayment_capture_mode"
        case minimumDurationMinutes = "minimum_duration_minutes"
        case effectiveRuleName = "effective_rule_name"
    }

    var isBookable: Bool { isFull != true && isBlocked != true && isBlockedByTime != true }

    /// Güncel API her tarihli slotta kuralı da gönderir (`prepayment_required` ve `booking_mode` hiç boş gelmez).
    var carriesRule: Bool { prepaymentRequired != nil || bookingMode != nil }
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

    /// Belirli bir gün için slotlar ve o günün müsaitlik durumu. Her seçenekteki `slot`,
    /// haftalık şablona o tarihte geçerli kural uygulanmış hâlidir.
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
            return SlotOption(slot: slot.applying(status), status: status, isBookable: bookable, dayBlockedReason: blockedDay ? dayInfo?.blockedReason : nil)
        }
        .sorted { $0.slot.startTime < $1.slot.startTime }
    }
}

struct SlotOption: Hashable, Identifiable {
    /// O tarihte geçerli kural uygulanmış slot: kararlar, rozetler, tutarlar ve web devri bunu kullanır.
    let slot: PublicSlot
    let status: SlotAvailability?
    let isBookable: Bool
    let dayBlockedReason: String?

    var id: Int { slot.id }
}
