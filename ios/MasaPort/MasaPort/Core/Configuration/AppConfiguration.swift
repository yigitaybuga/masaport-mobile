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
    static func webReservationURL(venueID: Int, date: String, startTime: String?, guestCount: Int) -> URL {
        var components = URLComponents(url: bookingBaseURL.appending(path: "public/reservation/\(venueID)"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "guestCount", value: String(guestCount)),
            URLQueryItem(name: "reservationDate", value: date),
            URLQueryItem(name: "funnel_source", value: "masaport_ios"),
        ]
        if let startTime { items.append(URLQueryItem(name: "start_time", value: startTime)) }
        components.queryItems = items
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
