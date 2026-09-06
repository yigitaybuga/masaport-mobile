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
    let kvkkConsent: Bool
    let source = "masaport_ios"

    enum CodingKeys: String, CodingKey {
        case venueId = "venue_id"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case customerEmail = "customer_email"
        case reservationDate = "reservation_date"
        case guestCount = "guest_count"
        case timeSlotId = "time_slot_id"
        case note, source
        case kvkkConsent = "kvkk_consent"
    }
}

/// Sunucu `data.data` altında çift sarmalı döner; iç veri hem onay hem ödeme alanlarını taşıyabilir.
struct ReservationCreateResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: ReservationCreated?
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
        case amount, paymentId, provider, method, checkoutUrl, htmlContent, holdExpiresAt, reservationHoldId, reservationHoldUuid
    }

    var needsPayment: Bool { paymentId != nil || requiresPayment == true }
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

    enum CodingKeys: String, CodingKey {
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case guestCount = "guest_count"
        case participants, notes
        case couponCode = "coupon_code"
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
}

struct EmptyResponse: Decodable {}
struct EmptyBody: Encodable {}
