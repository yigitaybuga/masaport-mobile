import Foundation

// MARK: - Restoran rezervasyonu

struct ReservationRequest: Encodable {
    let venueId: Int
    let customerName: String
    let customerPhone: String
    let customerEmail: String?
    let reservationDate: String
    let guestCount: Int
    let timeSlotId: Int
    let note: String?
    /// Sabit anahtar (`ReservationOccasion`); boşsa gönderilmez.
    var occasion: String? = nil
    /// Yalnızca bu rezervasyon için misafirin seçtiği diyet/oturma tercihleri.
    var guestPreferences: CustomerPreferences? = nil
    let kvkkConsent: Bool
    var paymentHandoff = false
    let source = "masaport_ios"

    enum CodingKeys: String, CodingKey {
        case venueId = "venue_id"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case customerEmail = "customer_email"
        case reservationDate = "reservation_date"
        case guestCount = "guest_count"
        case timeSlotId = "time_slot_id"
        case note, source, occasion
        case guestPreferences = "guest_preferences"
        case kvkkConsent = "kvkk_consent"
        case paymentHandoff = "payment_handoff"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(venueId, forKey: .venueId)
        try container.encode(customerName, forKey: .customerName)
        try container.encode(customerPhone, forKey: .customerPhone)
        try container.encodeIfPresent(customerEmail, forKey: .customerEmail)
        try container.encode(reservationDate, forKey: .reservationDate)
        try container.encode(guestCount, forKey: .guestCount)
        try container.encode(timeSlotId, forKey: .timeSlotId)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(occasion, forKey: .occasion)
        if let guestPreferences, !guestPreferences.isEmpty {
            try container.encode(guestPreferences, forKey: .guestPreferences)
        }
        try container.encode(kvkkConsent, forKey: .kvkkConsent)
        try container.encode(paymentHandoff, forKey: .paymentHandoff)
        try container.encode(source, forKey: .source)
    }
}

/// Rezervasyonda seçilebilen özel gün; anahtarlar API ile aynıdır.
enum ReservationOccasion: String, CaseIterable, Identifiable {
    case birthday, anniversary
    case dateNight = "date_night"
    case business, celebration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .birthday: "Doğum günü"
        case .anniversary: "Yıl dönümü"
        case .dateNight: "Romantik akşam"
        case .business: "İş yemeği"
        case .celebration: "Kutlama"
        }
    }

    var systemImage: String {
        switch self {
        case .birthday: "birthday.cake"
        case .anniversary, .dateNight: "heart"
        case .business: "briefcase"
        case .celebration: "party.popper"
        }
    }
}

/// Onay ve ödeme cevapları `data.data` altında çift sarmalı döner. Giriş yapılmış kullanıcının
/// ödeme aktarımı (`payment_handoff`) ise tek sarmallıdır: bekletme alanları doğrudan dış `data`
/// içindedir. İki biçim de aynı `ReservationCreated` değerine çözülür.
struct ReservationCreateResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: ReservationCreated?

    enum CodingKeys: String, CodingKey { case success, message, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let nested = try? container.decodeIfPresent(ReservationCreated.self, forKey: .data), nested.hasPayload {
            data = nested
        } else {
            let flat = try ReservationCreated(from: decoder)
            data = flat.hasPayload ? flat : nil
        }
    }
}

struct ReservationCreated: Decodable, Hashable {
    let reservationId: Int?
    /// Check-in QR'ı için (`/qr/:uuid`).
    let reservationUuid: String?
    let reservationStatus: String?
    let startTime: String?
    let endTime: String?
    let requiresManualApproval: Bool?
    let bookingMode: String?
    let bookingMessage: String?
    let requiresPayment: Bool?
    let amount: APINumber?
    // Ön ödeme akışı
    let paymentId: String?
    let provider: String?
    let method: String?
    let checkoutUrl: String?
    let htmlContent: String?
    let holdExpiresAt: String?
    let reservationHoldId: Int?
    let reservationHoldUuid: String?
    /// Ödeme cevabında: `PREAUTH` ise tutar kartta bloke edilir, çekilmez.
    let prepaymentCaptureMode: String?
    /// İptal/değişiklik talebi için imzalı misafir bağlantısı (app.masaport `/public/reservation/manage/:uuid#token=`).
    let managementUrl: String?

    enum CodingKeys: String, CodingKey {
        case reservationId = "reservation_id"
        case reservationUuid = "reservation_uuid"
        case reservationStatus = "reservation_status"
        case startTime = "start_time"
        case endTime = "end_time"
        case requiresManualApproval = "requires_manual_approval"
        case bookingMode = "booking_mode"
        case bookingMessage = "booking_message"
        case requiresPayment = "requires_payment"
        case managementUrl = "management_url"
        case amount, paymentId, provider, method, checkoutUrl, htmlContent, holdExpiresAt, reservationHoldId, reservationHoldUuid, prepaymentCaptureMode
    }

    var needsPayment: Bool { paymentId != nil || requiresPayment == true }

    /// Boş bir nesne (ör. `data: {}`) geçerli bir cevap sayılmaz.
    var hasPayload: Bool {
        reservationId != nil || reservationHoldId != nil || paymentId != nil || requiresPayment != nil
    }
}

// MARK: - Masa bekletmesi

struct ReservationHoldCancelRequest: Encodable {
    let holdUuid: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case holdUuid = "hold_uuid"
        case reason
    }
}

/// `POST /reservations/holds/:holdId/cancel` cevabı. Ödemeyle rezervasyona dönüşmüş bekletmeyi
/// sunucu iptal etmez (`cancelled: false`, `status: COMPLETED`).
struct ReservationHoldCancelResult: Decodable, Hashable {
    let holdId: Int?
    let status: String?
    let cancelled: Bool?

    var wasConverted: Bool { status?.uppercased() == "COMPLETED" }
}

// MARK: - Etkinlik rezervasyonu

struct EventReservationRequest: Encodable {
    struct Participant: Encodable { let name: String }

    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let guestCount: Int
    let participants: [Participant]?
    let notes: String?
    let couponCode: String?
    /// Bilet seçeneği tanımlı etkinliklerde zorunlu; diğerlerinde gönderilmez.
    var ticketOptionId: String? = nil

    enum CodingKeys: String, CodingKey {
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case guestCount = "guest_count"
        case participants, notes
        case couponCode = "coupon_code"
        case ticketOptionId = "ticket_option_id"
    }
}

struct EventReservationCreateResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: EventReservationCreated?
}

struct EventReservationCreated: Decodable, Hashable {
    let id: Int?
    let uuid: String?
    let eventInstanceId: Int?
    let contactName: String?
    let guestCount: Int?
    let paymentStatus: String?
    let totalAmount: APINumber?
    // Ödeme akışı
    let paymentId: String?
    let provider: String?
    let checkoutUrl: String?
    let htmlContent: String?
    let holdExpiresAt: String?
    let reservationHoldId: Int?
    let reservationHoldUuid: String?

    var needsPayment: Bool { paymentId != nil }
}

// MARK: - Ödeme

struct PaymentConfig: Decodable, Hashable {
    let provider: String?
    let checkoutMethod: String?
    let requiresCardDetails: Bool?
    let environment: String?

    /// Kart bilgisi istemeyen (hosted) sağlayıcılarda ödeme uygulama içinde Safari ile tamamlanabilir.
    var supportsHostedCheckout: Bool { requiresCardDetails == false }
}

struct PaymentStatus: Decodable, Hashable {
    let id: String?
    let status: String?
    let errorMessage: String?
    let reservationId: Int?
    /// Ödeme başarılıysa oluşan restoran rezervasyonunun UUID'si (QR için).
    let reservationUuid: String?

    var isFinal: Bool { ["SUCCESS", "FAILED", "CANCELLED"].contains(status ?? "") }
    var isSuccess: Bool { status == "SUCCESS" }
    /// Ödeme kesin olarak tamamlanmadı; bekletme güvenle bırakılabilir.
    var isFailure: Bool { ["FAILED", "CANCELLED"].contains(status ?? "") }
}

// MARK: - Misafir rezervasyon yönetimi

/// `GET /public/reservations/:uuid/manage`: imzalı misafir bağlantısıyla rezervasyonun güncel hâli.
struct GuestManagedReservation: Decodable, Hashable {
    let uuid: String?
    let reservationDate: String?
    let startTime: String?
    let endTime: String?
    let guestCount: Int?
    let status: String?
}

struct EmptyResponse: Decodable {}
struct EmptyBody: Encodable {}
