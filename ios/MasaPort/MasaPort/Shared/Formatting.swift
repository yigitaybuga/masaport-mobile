import Foundation

extension Calendar {
    static let istanbul: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        return calendar
    }()
}

enum DateFormat {
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = format
        return formatter
    }

    /// API'nin beklediği `YYYY-MM-DD`.
    static let apiDay = make("yyyy-MM-dd")
    static let dayMonth = make("d MMM")
    static let dayMonthLong = make("d MMMM")
    static let weekdayShort = make("EEE")
    static let weekdayLong = make("EEEE")
    static let longDay = make("d MMMM EEEE")
    static let time = make("HH:mm")
    static let dateTime = make("d MMM EEE, HH:mm")
    static let fullDateTime = make("d MMMM yyyy EEEE, HH:mm")
    static let monthYear = make("MMMM yyyy")

    static func parseAPIDay(_ value: String) -> Date? { apiDay.date(from: value) }
}

enum Format {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func price(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return currency.string(from: NSNumber(value: value))
    }

    static func rating(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return String(format: "%.1f", value)
    }

    static func distance(_ km: Double?) -> String? {
        guard let km else { return nil }
        if km < 1 { return "\(Int((km * 1000).rounded())) m" }
        return String(format: "%.1f km", km)
    }

    /// "Bugün", "Yarın" veya "12 Eyl Cum".
    static func relativeDay(_ date: Date, calendar: Calendar = .istanbul) -> String {
        if calendar.isDateInToday(date) { return "Bugün" }
        if calendar.isDateInTomorrow(date) { return "Yarın" }
        return "\(DateFormat.weekdayShort.string(from: date)) \(DateFormat.dayMonth.string(from: date))"
    }

    static func eventDate(_ date: Date?, calendar: Calendar = .istanbul) -> String {
        guard let date else { return "Tarih açıklanacak" }
        return "\(relativeDay(date, calendar: calendar)) · \(DateFormat.time.string(from: date))"
    }

    static func guests(_ count: Int) -> String { "\(count) kişi" }

    static func daypartGreeting(now: Date = .now, calendar: Calendar = .istanbul) -> String {
        switch calendar.component(.hour, from: now) {
        case 5..<11: "Günaydın"
        case 11..<17: "İyi günler"
        case 17..<22: "İyi akşamlar"
        default: "İyi geceler"
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var shortTime: String { String(prefix(5)) }
}

extension URL {
    /// Göreli `/uploads/...` yollarını API köküne bağlar; mutlak adresleri olduğu gibi bırakır.
    static func media(_ raw: String?) -> URL? {
        guard let raw = raw?.nilIfBlank else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        return AppConfiguration.apiRootURL.appending(path: raw.hasPrefix("/") ? String(raw.dropFirst()) : raw)
    }
}
