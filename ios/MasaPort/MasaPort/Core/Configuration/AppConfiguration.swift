import Foundation

enum AppConfiguration {
    static let apiBaseURL: URL = infoURL("MASAPORT_API_BASE_URL")
    static let webBaseURL: URL = infoURL("MASAPORT_WEB_BASE_URL")
    /// app.masaport.com – ön ödemeli akışların web'e devredildiği adres.
    static let bookingBaseURL: URL = infoURL("MASAPORT_BOOKING_BASE_URL")

    /// Kök API adresi (`/api` öneki olmadan). `/qr/:uuid` gibi kökte servis edilen yollar için.
    static var apiRootURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = ""
        components.query = nil
        return components.url!
    }

    static func qrImageURL(uuid: String) -> URL {
        apiRootURL.appending(path: "qr/\(uuid)")
    }

    static func calendarURL(uuid: String) -> URL {
        apiBaseURL.appending(path: "public/reservations/\(uuid)/calendar.ics")
    }

    /// masaport.com'daki restoran sayfası (paylaşım için).
    static func listingShareURL(citySlug: String?, slug: String) -> URL {
        if let citySlug, !citySlug.isEmpty {
            return webBaseURL.appending(path: "\(citySlug)/restoranlar/\(slug)")
        }
        return webBaseURL.appending(path: "restaurant/\(slug)")
    }

    static func eventShareURL(eventID: Int) -> URL {
        webBaseURL.appending(path: "etkinlikler/\(eventID)")
    }

    /// Ön ödeme gerektiren restoran rezervasyonları web akışına devredilir.
    static func webReservationURL(
        venueID: Int,
        date: String,
        guestCount: Int,
        slot: PublicSlot?,
        customerName: String? = nil,
        customerPhone: String? = nil,
        customerEmail: String? = nil,
        note: String? = nil,
        paymentOnly: Bool = false,
        reservationHoldID: Int? = nil,
        reservationHoldUUID: String? = nil,
        holdExpiresAt: String? = nil
    ) -> URL {
        var components = URLComponents(url: bookingBaseURL.appending(path: "public/reservation/\(venueID)"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "guestCount", value: String(guestCount)),
            URLQueryItem(name: "reservationDate", value: date),
            URLQueryItem(name: "funnel_source", value: "masaport_ios"),
        ]
        if let slot {
            items.append(URLQueryItem(name: "timeSlotId", value: String(slot.id)))
            items.append(URLQueryItem(name: "start_time", value: slot.startTime.shortTime))
            items.append(URLQueryItem(name: "end_time", value: slot.endTime?.shortTime))
            items.append(URLQueryItem(name: "prepayment_required", value: String(slot.prepaymentRequired == true)))
            items.append(URLQueryItem(name: "prepayment_total_amount", value: slot.prepaymentTotalAmount?.value.map { String($0) }))
            items.append(URLQueryItem(name: "prepayment_summary", value: slot.prepaymentSummary?.nilIfBlank))
            items.append(URLQueryItem(name: "minimum_spend_required", value: String(slot.minimumSpendRequired == true)))
            items.append(URLQueryItem(name: "minimum_spend_summary", value: slot.minimumSpendSummary?.nilIfBlank))
            items.append(URLQueryItem(name: "minimum_duration_minutes", value: slot.durationMinutes.map { String($0) }))
        }
        if paymentOnly {
            items.append(URLQueryItem(name: "payment_only", value: "true"))
        }
        items.removeAll { $0.value == nil }
        components.queryItems = items

        // Kişisel bilgileri HTTP isteğine ve sunucu loglarına giren query yerine fragment'te taşı.
        var privateComponents = URLComponents()
        privateComponents.queryItems = [
            URLQueryItem(name: "customer_name", value: customerName?.nilIfBlank),
            URLQueryItem(name: "customer_email", value: customerEmail?.nilIfBlank),
            URLQueryItem(name: "customer_phone", value: customerPhone?.nilIfBlank),
            URLQueryItem(name: "reservation_note", value: note?.nilIfBlank),
            URLQueryItem(name: "hold_id", value: reservationHoldID.map { String($0) }),
            URLQueryItem(name: "hold_uuid", value: reservationHoldUUID?.nilIfBlank),
            URLQueryItem(name: "hold_expires_at", value: holdExpiresAt?.nilIfBlank),
        ].filter { $0.value != nil }
        components.percentEncodedFragment = privateComponents.percentEncodedQuery

        return components.url!
    }

    static func webEventTicketURL(eventID: Int) -> URL {
        bookingBaseURL.appending(path: "events/public/\(eventID)")
    }

    private static func infoURL(_ key: String) -> URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            preconditionFailure("\(key) must be a valid URL.")
        }
        return url
    }
}
