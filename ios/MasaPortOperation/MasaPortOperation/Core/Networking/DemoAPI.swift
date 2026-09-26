#if DEBUG
import Foundation

/// Yalnızca Debug derlemelerinde, `MASAPORT_DEMO=1` ortam değişkeni veya `-masaport-demo`
/// başlatma argümanıyla açılır. Ağ isteklerini bellek içi örnek verilerle yanıtlar; böylece
/// tasarım ve akışlar gerçek API'ye ya da veritabanına dokunmadan denenebilir.
enum DemoMode {
    static let isEnabled: Bool = {
        let process = ProcessInfo.processInfo
        return process.environment["MASAPORT_DEMO"] == "1" || process.arguments.contains("-masaport-demo")
    }()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.readBody(of: request)
        let (statusCode, data) = DemoStore.shared.respond(method: request.httpMethod ?? "GET", url: url, body: body)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Store

final class DemoStore {
    static let shared = DemoStore()

    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var reservations: [Reservation]
    private var tables: [VenueTable]
    private var waitlist: [WaitlistEntry]
    private var events: [DemoEvent] = []
    private var eventReservations: [EventReservation] = [] {
        didSet { eventReservationsSnapshot = eventReservations }
    }
    fileprivate private(set) var eventReservationsSnapshot: [EventReservation] = []

    /// Giriş ekranı ve tarayıcıda ipucu olarak gösterilen örnek kısa kod.
    var sampleShortCode: String {
        lock.lock(); defer { lock.unlock() }
        return String((reservations.first?.uuid ?? "").suffix(8)).lowercased()
    }

    private let venue = Venue(id: 12, name: "Nova Bistro Karaköy", timezone: "Europe/Istanbul", logo: nil)
    private let secondVenue = Venue(id: 13, name: "Nova Teras Moda", timezone: "Europe/Istanbul", logo: nil)
    private let user = OperationUser(
        id: 1,
        name: "Yiğit Yalçın",
        email: "yigit@novabistro.com",
        venueRoles: [
            VenueRoleAssignment(venueId: 12, role: .manager),
            VenueRoleAssignment(venueId: 13, role: .host)
        ]
    )

    init() {
        let now = Date()
        let seedTables: [VenueTable] = [
            VenueTable(id: 1, name: "A1", capacity: 2, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 2, name: "A2", capacity: 2, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 3, name: "A3", capacity: 4, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 4, name: "A4", capacity: 4, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 5, name: "A5", capacity: 4, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 6, name: "A6", capacity: 4, zone: "Salon", serviceStatus: "EMPTY"),
            VenueTable(id: 7, name: "B1", capacity: 4, zone: "Bahçe", serviceStatus: "SEATED"),
            VenueTable(id: 8, name: "B2", capacity: 6, zone: "Bahçe", serviceStatus: "EMPTY"),
            VenueTable(id: 9, name: "B3", capacity: 2, zone: "Bahçe", serviceStatus: "EMPTY"),
            VenueTable(id: 10, name: "T1", capacity: 2, zone: "Teras", serviceStatus: "EMPTY"),
            VenueTable(id: 11, name: "T2", capacity: 4, zone: "Teras", serviceStatus: "BILL"),
            VenueTable(id: 12, name: "T3", capacity: 8, zone: "Teras", serviceStatus: "EMPTY")
        ]

        tables = seedTables
        func table(_ id: Int) -> VenueTable { seedTables.first { $0.id == id }! }

        reservations = [
            Self.reservation(id: 101, start: now.addingTimeInterval(-40 * 60), guests: 2, name: "Elif Kaya", phone: "+90 532 111 22 33", tables: [table(2)]),
            Self.reservation(id: 102, start: now.addingTimeInterval(-25 * 60), guests: 4, name: "Mert Demir", phone: "+90 533 222 33 44", tables: [table(7)], service: "SEATED", checkedIn: true),
            Self.reservation(id: 103, start: now.addingTimeInterval(-75 * 60), guests: 3, name: "Ayşe Yılmaz", phone: "+90 535 333 44 55", tables: [table(11)], service: "BILL", checkedIn: true),
            Self.reservation(id: 104, start: now.addingTimeInterval(3 * 60), guests: 2, name: "Can Öztürk", phone: "+90 536 444 55 66", tables: []),
            Self.reservation(id: 105, start: now.addingTimeInterval(20 * 60), guests: 6, name: "Selin Arslan", phone: "+90 537 555 66 77", tables: [table(8)], note: "Doğum günü kutlaması, pastayı kendileri getirecek."),
            Self.reservation(id: 106, start: now.addingTimeInterval(35 * 60), guests: 2, name: "Okan Yıldız", phone: "+90 538 666 77 88", tables: []),
            Self.reservation(id: 107, start: now.addingTimeInterval(45 * 60), guests: 5, name: "Zeynep Koç", phone: "+90 539 777 88 99", tables: [], status: "PENDING"),
            Self.reservation(id: 108, start: now.addingTimeInterval(55 * 60), guests: 2, name: "Burak Şahin", phone: "+90 541 888 99 00", tables: [table(9)]),
            Self.reservation(id: 109, start: now.addingTimeInterval(150 * 60), guests: 4, name: "Deniz Aydın", phone: "+90 542 999 00 11", tables: [table(4)]),
            Self.reservation(id: 110, start: now.addingTimeInterval(-180 * 60), guests: 2, name: "Kerem Çelik", phone: "+90 543 000 11 22", tables: [table(1)], status: "COMPLETED", service: "LEFT", checkedIn: true),
            Self.reservation(id: 111, start: now.addingTimeInterval(-60 * 60), guests: 3, name: "Gizem Polat", phone: "+90 544 111 22 33", tables: [], status: "CANCELLED"),
            Self.reservation(id: 112, start: now.addingTimeInterval(24 * 3600 + 30 * 60), guests: 4, name: "Bora Kaplan", phone: "+90 548 555 66 77", tables: [table(3)]),
            Self.reservation(id: 113, start: now.addingTimeInterval(24 * 3600 + 90 * 60), guests: 2, name: "Nehir Acar", phone: "+90 549 666 77 88", tables: [], status: "PENDING")
        ]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Europe/Istanbul")
        day.dateFormat = "yyyy-MM-dd"
        let slot = { (offset: TimeInterval) -> WaitlistTimeSlot in
            let start = now.addingTimeInterval(offset)
            return WaitlistTimeSlot(
                id: Int(offset / 60),
                startTime: Self.timeString(start),
                endTime: Self.timeString(start.addingTimeInterval(90 * 60)),
                durationMinutes: 90
            )
        }
        waitlist = [
            WaitlistEntry(id: 201, venueID: 12, timeSlotID: 1, reservationDate: day.string(from: now), guestCount: 4, customerName: "Hakan Güneş", customerPhone: "+90 545 222 33 44", customerEmail: nil, status: "WAITING", source: "WEB", note: nil, createdAt: iso.string(from: now.addingTimeInterval(-25 * 60)), offerExpiresAt: nil, timeSlot: slot(30 * 60)),
            WaitlistEntry(id: 202, venueID: 12, timeSlotID: 2, reservationDate: day.string(from: now), guestCount: 2, customerName: "Merve Aksoy", customerPhone: "+90 546 333 44 55", customerEmail: nil, status: "OFFERED", source: "WEB", note: nil, createdAt: iso.string(from: now.addingTimeInterval(-50 * 60)), offerExpiresAt: iso.string(from: now.addingTimeInterval(9 * 60)), timeSlot: slot(15 * 60)),
            WaitlistEntry(id: 203, venueID: 12, timeSlotID: 3, reservationDate: day.string(from: now), guestCount: 3, customerName: "Emre Doğan", customerPhone: "+90 547 444 55 66", customerEmail: nil, status: "WAITING", source: "MOBILE", note: "Bebek sandalyesi gerekiyor.", createdAt: iso.string(from: now.addingTimeInterval(-5 * 60)), offerExpiresAt: nil, timeSlot: slot(60 * 60))
        ]

        let hour: TimeInterval = 3600
        events = [
            DemoEvent(
                id: 501, title: "Caz Gecesi: Trio Session", description: "Canlı caz üçlüsü eşliğinde akşam servisi.",
                maxCapacity: 60, paymentType: "FULL",
                instances: [
                    DemoInstance(id: 5011, start: now.addingTimeInterval(-0.5 * hour), end: now.addingTimeInterval(2 * hour))
                ]
            ),
            DemoEvent(
                id: 502, title: "Şarap Tadımı: Ege Bağları", description: "Sommelier eşliğinde 6 kadeh tadım menüsü.",
                maxCapacity: 24, paymentType: "PREPAYMENT",
                instances: [
                    DemoInstance(id: 5021, start: now.addingTimeInterval(26 * hour), end: now.addingTimeInterval(28 * hour)),
                    DemoInstance(id: 5022, start: now.addingTimeInterval(7 * 24 * hour + 2 * hour), end: now.addingTimeInterval(7 * 24 * hour + 4 * hour))
                ]
            ),
            DemoEvent(
                id: 503, title: "Pazar Brunch Atölyesi", description: "Ekşi maya ve kahvaltı sofrası atölyesi.",
                maxCapacity: 30, paymentType: "NONE",
                instances: [
                    DemoInstance(id: 5031, start: now.addingTimeInterval(-3 * 24 * hour), end: now.addingTimeInterval(-3 * 24 * hour + 3 * hour))
                ]
            )
        ]

        func eventReservation(_ id: Int, instance: DemoInstance, name: String, phone: String, guests: [String], payment: String, checkedIn: Bool, note: String? = nil) -> EventReservation {
            EventReservation(
                id: id,
                uuid: UUID().uuidString.lowercased(),
                eventInstanceId: instance.id,
                contactName: name,
                contactEmail: nil,
                contactPhone: phone,
                note: note,
                guestCount: guests.count,
                paymentStatus: payment,
                totalAmount: FlexibleDecimal(value: Double(guests.count) * 450),
                checkedIn: checkedIn,
                checkedInAt: checkedIn ? iso.string(from: now.addingTimeInterval(-20 * 60)) : nil,
                createdAt: iso.string(from: now.addingTimeInterval(-2 * 24 * hour)),
                eventGuests: guests.enumerated().map { EventGuest(id: id * 10 + $0.offset, fullName: $0.element) },
                eventInstance: EventReservationInstance(id: instance.id, startDatetime: Self.isoString(instance.start), endDatetime: Self.isoString(instance.end))
            )
        }
        let jazz = events[0].instances[0]
        let wine = events[1].instances[0]
        let brunch = events[2].instances[0]
        eventReservations = [
            eventReservation(601, instance: jazz, name: "Derya Kurt", phone: "+90 551 100 20 30", guests: ["Derya Kurt", "Ali Kurt"], payment: "PAID", checkedIn: true),
            eventReservation(602, instance: jazz, name: "Sinan Erdem", phone: "+90 552 200 30 40", guests: ["Sinan Erdem", "Ece Erdem", "Kaan Erdem", "Lale Erdem"], payment: "PAID", checkedIn: false, note: "Sahneye yakın masa rica ettiler."),
            eventReservation(603, instance: jazz, name: "Pelin Aksu", phone: "+90 553 300 40 50", guests: ["Pelin Aksu"], payment: "PAID", checkedIn: false),
            eventReservation(604, instance: jazz, name: "Tolga Berk", phone: "+90 554 400 50 60", guests: ["Tolga Berk", "Nil Berk"], payment: "PENDING", checkedIn: false),
            eventReservation(605, instance: jazz, name: "Yasemin Toprak", phone: "+90 555 500 60 70", guests: ["Yasemin Toprak", "Bora Toprak", "Ada Toprak"], payment: "PAID", checkedIn: true),
            eventReservation(606, instance: wine, name: "Cem Yalın", phone: "+90 556 600 70 80", guests: ["Cem Yalın", "İpek Yalın"], payment: "PAID", checkedIn: false),
            eventReservation(607, instance: wine, name: "Nazlı Güler", phone: "+90 557 700 80 90", guests: ["Nazlı Güler"], payment: "PENDING", checkedIn: false),
            eventReservation(608, instance: brunch, name: "Umut Sezer", phone: "+90 558 800 90 00", guests: ["Umut Sezer", "Melis Sezer"], payment: "PAID", checkedIn: true)
        ]
        eventReservationsSnapshot = eventReservations
        syncTableStates()
    }

    // MARK: Routing

    func respond(method: String, url: URL, body: Data) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }

        var parts = url.path.split(separator: "/").map(String.init)
        if parts.first == "api" { parts.removeFirst() }

        let count = parts.count
        func part(_ index: Int) -> String { index < count ? parts[index] : "" }

        if method == "POST", parts == ["mobile", "auth", "login"] || parts == ["mobile", "auth", "refresh"] {
            return ok(authPayload())
        }
        if method == "POST", parts == ["mobile", "auth", "logout"] {
            return ok(EmptyResponse())
        }
        if method == "GET", count == 2, part(0) == "reservations" {
            let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "date" }?.value
            return ok(date.map { day in reservations.filter { $0.reservationDate == day } } ?? reservations)
        }
        if method == "GET", count == 3, part(0) == "reservations", part(2) == "available-tables" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let guests = query.first { $0.name == "guest_count" }?.value.flatMap(Int.init) ?? 2
            return venueAvailableTables(guestCount: guests)
        }
        if method == "POST", count == 3, part(0) == "reservations", part(2) == "walk-in" {
            return createWalkIn(body: body)
        }
        if method == "GET", count == 3, part(0) == "reservations", let id = Int(part(2)) {
            guard let reservation = reservations.first(where: { $0.id == id }) else { return fail(404, "Rezervasyon bulunamadı") }
            return ok(reservation)
        }
        if method == "PUT", count == 3, part(0) == "reservations", let id = Int(part(2)) {
            return updateReservation(reservationID: id, body: body)
        }
        if method == "PUT", count == 4, part(0) == "reservations", part(3) == "status" {
            return updateStatus(reservationID: Int(part(2)) ?? 0, body: body)
        }
        if method == "POST", count == 4, part(0) == "reservations", part(3) == "no-show" {
            return markNoShow(reservationID: Int(part(2)) ?? 0, body: body)
        }
        if method == "GET", count == 2, part(0) == "tables" {
            return ok(tables)
        }
        if method == "GET", count == 2, part(0) == "waitlist" {
            return ok(waitlist)
        }
        if method == "POST", count == 3, part(0) == "checkin", part(1) == "restaurant" {
            return checkIn(identifier: part(2), body: body)
        }
        if method == "POST", count == 3, part(0) == "checkin", part(1) == "event" {
            return checkInEvent(identifier: part(2))
        }
        if method == "GET", count == 3, part(0) == "checkin", part(1) == "status" {
            return checkinStatus(identifier: part(2))
        }
        if method == "GET", count == 3, part(0) == "events", part(2) == "events" {
            return ok(events.map { $0.summary(now: Date()) })
        }
        if method == "PUT", count == 6, part(0) == "events", part(2) == "reservations", part(5) == "note" {
            struct Request: Decodable { let note: String? }
            let reservationID = Int(part(4)) ?? 0
            guard let index = eventReservations.firstIndex(where: { $0.id == reservationID }) else {
                return fail(404, "Event reservation not found")
            }
            let note = ((try? decoder.decode(Request.self, from: body))?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            eventReservations[index] = eventReservations[index].demoUpdating(note: note.isEmpty ? nil : note)
            return ok(EventReservationNoteResult(id: reservationID, note: note.isEmpty ? nil : note))
        }
        if method == "GET", count == 4, part(0) == "events", part(2) == "reservations" {
            let eventID = Int(part(3)) ?? 0
            let instanceID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "instance_id" }?.value.flatMap(Int.init)
            let instanceIDs = Set(events.first { $0.id == eventID }?.instances.map(\.id) ?? [])
            let matching = eventReservations.filter { reservation in
                guard let id = reservation.eventInstanceId, instanceIDs.contains(id) else { return false }
                return instanceID == nil || id == instanceID
            }
            return ok(matching)
        }
        if method == "GET", count == 4, part(0) == "reservations", part(3) == "available-tables" {
            return availableTables(reservationID: Int(part(2)) ?? 0)
        }
        if method == "PUT", count == 4, part(0) == "reservations", part(3) == "tables" {
            return assignTables(reservationID: Int(part(2)) ?? 0, body: body)
        }
        if method == "PUT", count == 4, part(0) == "reservations", part(3) == "service-status" {
            return updateServiceStatus(reservationID: Int(part(2)) ?? 0, body: body)
        }
        if method == "POST", count == 5, part(0) == "waitlist", part(2) == "entry", part(4) == "offer" {
            return offer(entryID: Int(part(3)) ?? 0)
        }
        if method == "PUT", count == 4, part(0) == "waitlist", part(1) == "entry", part(3) == "status" {
            return updateWaitlistStatus(entryID: Int(part(2)) ?? 0, body: body)
        }
        return fail(404, "Demo modunda tanımlı olmayan uç nokta: \(method) \(url.path)")
    }

    // MARK: Handlers

    private func authPayload() -> MobileAuthPayload {
        MobileAuthPayload(
            accessToken: "demo-access-token",
            refreshToken: "demo-refresh-token",
            expiresIn: 3600,
            tokenType: "Bearer",
            session: MobileSession(id: "demo-session", expiresAt: "2099-01-01T00:00:00.000Z", installationID: nil),
            user: user,
            venues: [venue, secondVenue]
        )
    }

    private func reservationIndex(matching identifier: String) -> Int? {
        let needle = identifier.lowercased()
        return reservations.firstIndex { $0.uuid.lowercased() == needle || $0.uuid.lowercased().hasSuffix(needle) }
    }

    private func eventReservationIndex(matching identifier: String) -> Int? {
        let needle = identifier.lowercased()
        return eventReservations.firstIndex { ($0.uuid ?? "").lowercased() == needle || ($0.uuid ?? "").lowercased().hasSuffix(needle) }
    }

    private func checkIn(identifier: String, body: Data) -> (Int, Data) {
        guard let index = reservationIndex(matching: identifier) else {
            return fail(404, "Rezervasyon bulunamadı")
        }
        let reservation = reservations[index]
        if reservation.checkedIn {
            return fail(400, "Bu rezervasyon zaten check-in yapılmış")
        }
        if reservation.status.uppercased() != "CONFIRMED" {
            return fail(400, "Sadece onaylanmış rezervasyonlar check-in yapılabilir")
        }
        let force = (try? decoder.decode(RestaurantCheckinRequest.self, from: body))?.forceCheckIn ?? false
        let minutes = reservation.minutesUntilStart() ?? 0
        if minutes > 15 && !force {
            return fail(400, "EARLY_CHECKIN_WARNING", message: "Rezervasyon saatine daha \(minutes) dakika var. Erken check-in yapmak istediğinizden emin misiniz?")
        }
        reservations[index] = reservation.updatingServiceStatus(
            ReservationServiceStatusUpdate(serviceStatus: "SEATED", status: "CONFIRMED", checkedIn: true, updatedAt: Self.nowString())
        )
        syncTableStates()
        let updated = reservations[index]
        return ok(CheckinPayload(success: true, data: CheckinResult(
            id: updated.id, uuid: updated.uuid, venue: venue.name, guestCount: updated.guestCount,
            customerName: updated.customerName, contactName: nil, eventTitle: nil,
            tables: updated.tables.map(\.name), checkedInAt: Self.nowString()
        ), error: nil, message: "Rezervasyon başarıyla check-in yapıldı"))
    }

    private func checkInEvent(identifier: String) -> (Int, Data) {
        guard let index = eventReservationIndex(matching: identifier) else {
            return fail(404, "Etkinlik rezervasyonu bulunamadı")
        }
        let reservation = eventReservations[index]
        if reservation.isCheckedIn {
            return fail(400, "Bu etkinlik rezervasyonu zaten check-in yapılmış")
        }
        if !reservation.isPaid {
            return fail(400, "Sadece ödemesi yapılmış etkinlik rezervasyonları check-in yapılabilir")
        }
        eventReservations[index] = reservation.demoCheckedIn(at: Self.nowString())
        let event = events.first { $0.instances.contains { $0.id == reservation.eventInstanceId } }
        return ok(CheckinPayload(success: true, data: CheckinResult(
            id: reservation.id, uuid: reservation.uuid ?? "", venue: venue.name, guestCount: reservation.guestCount,
            customerName: nil, contactName: reservation.contactName, eventTitle: event?.title,
            tables: nil, checkedInAt: Self.nowString()
        ), error: nil, message: "Etkinlik rezervasyonu başarıyla check-in yapıldı"))
    }

    private func checkinStatus(identifier: String) -> (Int, Data) {
        if let index = reservationIndex(matching: identifier) {
            let reservation = reservations[index]
            let minutes = reservation.minutesUntilStart() ?? 0
            let early = minutes > 15 && !reservation.checkedIn
            let status = CheckinStatus(
                type: "restaurant", id: reservation.id, uuid: reservation.uuid, venue: venue.name,
                guestCount: reservation.guestCount, status: reservation.status, paymentStatus: nil,
                checkedIn: reservation.checkedIn, checkedInAt: reservation.checkedIn ? reservation.updatedAt : nil,
                reservationDate: reservation.reservationDate, startTime: reservation.startTime,
                tables: reservation.tables.map(\.name), eventTitle: nil,
                customerName: reservation.customerName, customerPhone: reservation.customerPhone, contactName: nil,
                eventStartTime: nil, canCheckIn: !early,
                checkInWarning: early ? "Rezervasyon saatine daha \(minutes) dakika var. Erken check-in için onay gerekli." : nil,
                minutesUntilReservation: max(0, minutes)
            )
            return ok(CheckinPayload(success: true, data: status, error: nil, message: nil))
        }
        if let index = eventReservationIndex(matching: identifier) {
            let reservation = eventReservations[index]
            let event = events.first { $0.instances.contains { $0.id == reservation.eventInstanceId } }
            let status = CheckinStatus(
                type: "event", id: reservation.id, uuid: reservation.uuid ?? "", venue: venue.name,
                guestCount: reservation.guestCount, status: nil, paymentStatus: reservation.paymentStatus,
                checkedIn: reservation.checkedIn, checkedInAt: reservation.checkedInAt,
                reservationDate: nil, startTime: nil, tables: nil, eventTitle: event?.title,
                customerName: nil, customerPhone: reservation.contactPhone, contactName: reservation.contactName,
                eventStartTime: reservation.eventInstance?.startDatetime, canCheckIn: true,
                checkInWarning: nil, minutesUntilReservation: nil
            )
            return ok(CheckinPayload(success: true, data: status, error: nil, message: nil))
        }
        return fail(404, "Rezervasyon bulunamadı")
    }

    private func availableTables(reservationID: Int) -> (Int, Data) {
        guard let reservation = reservations.first(where: { $0.id == reservationID }) else {
            return fail(404, "Rezervasyon bulunamadı.")
        }
        let currentIDs = Set(reservation.tables.map(\.id))
        let occupiedIDs = Set(
            reservations
                .filter { $0.id != reservationID && $0.isInside }
                .flatMap { $0.tables.map(\.id) }
        )
        let options = tables.map { table in
            AssignableTable(
                id: table.id,
                name: table.name,
                capacity: table.capacity,
                zone: table.zone,
                isAvailable: !occupiedIDs.contains(table.id),
                isCurrent: currentIDs.contains(table.id),
                isRecommended: !occupiedIDs.contains(table.id)
                    && table.capacity >= reservation.guestCount
                    && table.capacity <= reservation.guestCount + 2
            )
        }
        return ok(ReservationTableAvailability(tables: options))
    }

    private func assignTables(reservationID: Int, body: Data) -> (Int, Data) {
        struct Request: Decodable {
            let tableIDs: [Int]
            enum CodingKeys: String, CodingKey { case tableIDs = "table_ids" }
        }
        guard let index = reservations.firstIndex(where: { $0.id == reservationID }),
              let request = try? decoder.decode(Request.self, from: body) else {
            return fail(400, "Geçersiz masa ataması.")
        }
        let updates = tables
            .filter { request.tableIDs.contains($0.id) }
            .map { ReservationTableUpdate(id: $0.id, name: $0.name, capacity: $0.capacity) }
        let result = ReservationTableAssignment(tables: updates, updatedAt: Self.nowString())
        reservations[index] = reservations[index].updatingTables(updates, updatedAt: result.updatedAt)
        return ok(result)
    }

    private func updateServiceStatus(reservationID: Int, body: Data) -> (Int, Data) {
        struct Request: Decodable {
            let serviceStatus: String
            enum CodingKeys: String, CodingKey { case serviceStatus = "service_status" }
        }
        guard let index = reservations.firstIndex(where: { $0.id == reservationID }),
              let request = try? decoder.decode(Request.self, from: body) else {
            return fail(400, "Geçersiz servis durumu.")
        }
        let rawService = request.serviceStatus.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let legacyStatusMap = [
            "ARRIVED": "SEATED",
            "BILL": "SEATED",
            "CLEANING": "LEFT",
            "EMPTY": "LEFT"
        ]
        let service = legacyStatusMap[rawService] ?? rawService
        guard ["SEATED", "LEFT"].contains(service) else {
            return fail(400, "Servis durumu Oturdu veya Kalktı olmalı.")
        }
        let current = reservations[index]
        if ["CANCELLED", "NO_SHOW"].contains(current.status.uppercased()) {
            return fail(409, "İptal veya gelmedi durumundaki rezervasyonda servis güncellenemez.")
        }
        if service == "SEATED" && current.isTerminal {
            return fail(409, "Tamamlanmış rezervasyon yeniden oturdu olarak işaretlenemez.")
        }
        if service == "LEFT" && !current.checkedIn {
            return fail(409, "Yalnızca check-in yapılmış rezervasyon kalktı olarak işaretlenebilir.")
        }
        let update = ReservationServiceStatusUpdate(
            serviceStatus: service,
            status: ["LEFT", "CLEANING", "EMPTY"].contains(service) ? "COMPLETED" : "CONFIRMED",
            checkedIn: true,
            updatedAt: Self.nowString()
        )
        reservations[index] = reservations[index].updatingServiceStatus(update)
        syncTableStates()
        return ok(update)
    }

    /// Masaların servis durumunu içerideki rezervasyonlardan türetir.
    private func syncTableStates() {
        tables = tables.map { table in
            let active = reservations.first { reservation in
                reservation.isInside && reservation.tables.contains { $0.id == table.id }
            }
            return VenueTable(id: table.id, name: table.name, capacity: table.capacity, zone: table.zone, serviceStatus: active?.serviceStatus ?? "EMPTY")
        }
    }

    private func occupiedTableIDs(excluding reservationID: Int? = nil) -> Set<Int> {
        Set(
            reservations
                .filter { $0.id != reservationID && $0.isInside }
                .flatMap { $0.tables.map(\.id) }
        )
    }

    private func venueAvailableTables(guestCount: Int) -> (Int, Data) {
        let occupied = occupiedTableIDs()
        let fitting = tables
            .filter { !occupied.contains($0.id) && $0.capacity >= guestCount }
            .sorted { $0.capacity < $1.capacity }
        let recommendedID = fitting.first?.id
        let options = tables.map { table in
            AssignableTable(
                id: table.id, name: table.name, capacity: table.capacity, zone: table.zone,
                isAvailable: !occupied.contains(table.id),
                isCurrent: false,
                isRecommended: table.id == recommendedID
            )
        }
        return ok(ReservationTableAvailability(tables: options))
    }

    private func createWalkIn(body: Data) -> (Int, Data) {
        guard let request = try? decoder.decode(WalkInRequest.self, from: body) else {
            return fail(400, "Geçersiz walk-in isteği.")
        }
        let occupied = occupiedTableIDs()
        var chosen: [VenueTable] = []
        if let ids = request.tableIDs, !ids.isEmpty {
            chosen = tables.filter { ids.contains($0.id) }
            if chosen.contains(where: { occupied.contains($0.id) }) {
                return fail(409, "Seçilen masalardan biri şu an dolu.")
            }
        } else if let auto = tables
            .filter({ !occupied.contains($0.id) && $0.capacity >= request.guestCount })
            .min(by: { $0.capacity < $1.capacity }) {
            chosen = [auto]
        }
        guard !chosen.isEmpty else {
            return fail(409, "Bu saat için uygun masa bulunamadı. Farklı bir saat seçin veya mevcut masa planını kontrol edin.")
        }
        let start: Date = {
            guard let time = request.startTime else { return Date() }
            let today = OperationDate.today()
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.date(from: "\(today) \(time)") ?? Date()
        }()
        let id = (reservations.map(\.id).max() ?? 100) + 1
        let base = Self.reservation(
            id: id, start: start, guests: request.guestCount, name: request.customerName, phone: request.customerPhone,
            tables: chosen, status: "CONFIRMED", service: request.checkedIn ? "SEATED" : nil,
            checkedIn: request.checkedIn, note: request.note
        )
        let duration = TimeInterval((request.durationMinutes ?? 90) * 60)
        let created = Reservation(
            id: base.id, uuid: base.uuid, reservationDate: base.reservationDate, startTime: base.startTime,
            endTime: Self.timeString(start.addingTimeInterval(duration)), guestCount: base.guestCount, status: base.status,
            serviceStatus: base.serviceStatus, customerName: base.customerName, customerPhone: base.customerPhone,
            note: base.note, tables: base.tables, checkedIn: base.checkedIn, updatedAt: base.updatedAt
        )
        reservations.append(created)
        syncTableStates()
        return (201, (try? encoder.encode(Envelope(success: true, data: WalkInResult(
            reservationID: created.id, reservationUUID: created.uuid,
            tables: chosen.map { ReservationTableUpdate(id: $0.id, name: $0.name, capacity: $0.capacity) },
            startTime: String(created.startTime.prefix(5)), endTime: String(created.endTime.prefix(5)),
            checkedIn: request.checkedIn
        ), error: nil, message: "Walk-in reservation created successfully"))) ?? Data())
    }

    private func updateReservation(reservationID: Int, body: Data) -> (Int, Data) {
        guard let index = reservations.firstIndex(where: { $0.id == reservationID }),
              let request = try? decoder.decode(ReservationUpdateRequest.self, from: body) else {
            return fail(400, "Geçersiz güncelleme isteği.")
        }
        let current = reservations[index]
        if request.expectedUpdatedAt != current.updatedAt {
            return fail(409, "RESOURCE_CONFLICT", message: "Rezervasyon başka bir cihazda değişti.")
        }
        var newStart: String? = nil
        var newEnd: String? = nil
        if let start = request.startTime {
            let duration = OperationDate.minutesBetween(current.startTime, current.endTime) ?? 90
            newStart = "\(start):00"
            newEnd = OperationDate.timeString(adding: duration, to: start) + ":00"
            let occupied = occupiedTableIDs(excluding: current.id)
            let conflicts = current.tables.filter { occupied.contains($0.id) }.map(\.name)
            if !conflicts.isEmpty {
                return fail(409, "TABLE_CONFLICT", message: "Yeni saatte şu masalar dolu: \(conflicts.joined(separator: ", ")). Önce masa atamasını değiştirin.")
            }
        }
        reservations[index] = current.updating(
            customerName: request.customerName ?? current.customerName,
            customerPhone: request.customerPhone ?? current.customerPhone,
            guestCount: request.guestCount ?? current.guestCount,
            note: request.note ?? current.note,
            startTime: newStart, endTime: newEnd,
            updatedAt: Self.nowString()
        )
        return ok(EmptyResponse())
    }

    private func updateStatus(reservationID: Int, body: Data) -> (Int, Data) {
        struct Request: Decodable { let status: String }
        guard let index = reservations.firstIndex(where: { $0.id == reservationID }),
              let request = try? decoder.decode(Request.self, from: body) else {
            return fail(400, "Geçersiz durum isteği.")
        }
        reservations[index] = reservations[index].updating(status: request.status.uppercased(), updatedAt: Self.nowString())
        syncTableStates()
        return ok(EmptyResponse())
    }

    private func markNoShow(reservationID: Int, body: Data) -> (Int, Data) {
        struct Request: Decodable { let reason: String }
        guard let index = reservations.firstIndex(where: { $0.id == reservationID }),
              let request = try? decoder.decode(Request.self, from: body) else {
            return fail(400, "Geçersiz istek.")
        }
        if request.reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            return fail(400, "No-show reason must be between 3 and 500 characters")
        }
        let reservation = reservations[index]
        if reservation.checkedIn || reservation.isTerminal {
            return fail(409, "Only an unseated pending or confirmed reservation can be marked as no-show")
        }
        reservations[index] = reservation.updating(status: "NO_SHOW", updatedAt: Self.nowString())
        return ok(EmptyResponse())
    }

    private func offer(entryID: Int) -> (Int, Data) {
        guard let index = waitlist.firstIndex(where: { $0.id == entryID }) else {
            return fail(404, "Bekleme kaydı bulunamadı.")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        waitlist[index] = waitlist[index].updating(status: "OFFERED", offerExpiresAt: iso.string(from: Date().addingTimeInterval(15 * 60)))
        return ok(WaitlistStatusPayload(id: entryID, status: "OFFERED"))
    }

    private func updateWaitlistStatus(entryID: Int, body: Data) -> (Int, Data) {
        struct Request: Decodable { let status: String }
        guard let index = waitlist.firstIndex(where: { $0.id == entryID }),
              let request = try? decoder.decode(Request.self, from: body) else {
            return fail(400, "Geçersiz bekleme durumu.")
        }
        if ["WAITING", "OFFERED"].contains(request.status.uppercased()) {
            waitlist[index] = waitlist[index].updating(status: request.status.uppercased(), offerExpiresAt: nil)
        } else {
            waitlist.remove(at: index)
        }
        return ok(WaitlistStatusPayload(id: entryID, status: request.status))
    }

    // MARK: Encoding

    private struct Envelope<Value: Encodable>: Encodable {
        let success: Bool
        let data: Value?
        let error: String?
        var message: String? = nil
    }

    private func ok<Value: Encodable>(_ value: Value) -> (Int, Data) {
        (200, (try? encoder.encode(Envelope(success: true, data: value, error: nil))) ?? Data())
    }

    private func fail(_ status: Int, _ error: String, message: String? = nil) -> (Int, Data) {
        (status, (try? encoder.encode(Envelope<EmptyResponse>(success: false, data: nil, error: error, message: message))) ?? Data())
    }

    static func isoString(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: date)
    }

    // MARK: Fixtures

    private static func reservation(
        id: Int,
        start: Date,
        guests: Int,
        name: String,
        phone: String,
        tables: [VenueTable],
        status: String = "CONFIRMED",
        service: String? = nil,
        checkedIn: Bool = false,
        note: String? = nil
    ) -> Reservation {
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Europe/Istanbul")
        day.dateFormat = "yyyy-MM-dd"
        return Reservation(
            id: id,
            uuid: "DEMO-\(id)-\(UUID().uuidString.prefix(8))",
            reservationDate: day.string(from: start),
            startTime: timeString(start),
            endTime: timeString(start.addingTimeInterval(90 * 60)),
            guestCount: guests,
            status: status,
            serviceStatus: service,
            customerName: name,
            customerPhone: phone,
            note: note,
            tables: tables,
            checkedIn: checkedIn,
            updatedAt: nowString()
        )
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func nowString() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: Date())
    }
}

private struct WaitlistStatusPayload: Encodable {
    let id: Int
    let status: String
}

private extension WaitlistEntry {
    func updating(status: String, offerExpiresAt: String?) -> WaitlistEntry {
        WaitlistEntry(
            id: id,
            venueID: venueID,
            timeSlotID: timeSlotID,
            reservationDate: reservationDate,
            guestCount: guestCount,
            customerName: customerName,
            customerPhone: customerPhone,
            customerEmail: customerEmail,
            status: status,
            source: source,
            note: note,
            createdAt: createdAt,
            offerExpiresAt: offerExpiresAt,
            timeSlot: timeSlot
        )
    }
}

private struct DemoInstance {
    let id: Int
    let start: Date
    let end: Date
}

private struct DemoEvent {
    let id: Int
    let title: String
    let description: String
    let maxCapacity: Int
    let paymentType: String
    let instances: [DemoInstance]

    func summary(now: Date) -> EventSummary {
        var active: EventInstanceSummary?
        var upcoming: [EventInstanceSummary] = []
        var past: [EventInstanceSummary] = []
        for instance in instances {
            let sold = DemoStore.shared.soldTickets(instanceID: instance.id)
            let summary = EventInstanceSummary(
                id: instance.id, eventId: id,
                startDatetime: DemoStore.isoString(instance.start), endDatetime: DemoStore.isoString(instance.end),
                soldTickets: sold
            )
            if instance.start <= now && instance.end >= now && active == nil {
                active = summary
            } else if instance.start < now {
                past.append(summary)
            } else {
                upcoming.append(summary)
            }
        }
        let first = instances.map(\.start).min() ?? now
        let last = instances.map(\.end).max() ?? now
        return EventSummary(
            id: id, venueId: 12, title: title, description: description, imageUrl: nil,
            startDatetime: DemoStore.isoString(first), endDatetime: DemoStore.isoString(last),
            maxCapacity: maxCapacity, paymentType: paymentType, isPublishedToPublic: true,
            activeInstance: active, upcomingInstances: upcoming, pastInstances: past
        )
    }
}

extension DemoStore {
    /// Kilit tutulurken çağrılır; Prisma'daki gibi satılan bilet = misafir sayısı toplamı.
    fileprivate func soldTickets(instanceID: Int) -> Int {
        eventReservationsSnapshot
            .filter { $0.eventInstanceId == instanceID }
            .reduce(0) { $0 + ($1.eventGuests?.count ?? $1.guestCount) }
    }
}

private extension EventReservation {
    func demoCheckedIn(at timestamp: String) -> EventReservation {
        EventReservation(
            id: id, uuid: uuid, eventInstanceId: eventInstanceId, contactName: contactName,
            contactEmail: contactEmail, contactPhone: contactPhone, note: note, guestCount: guestCount,
            paymentStatus: paymentStatus, totalAmount: totalAmount, checkedIn: true, checkedInAt: timestamp,
            createdAt: createdAt, eventGuests: eventGuests, eventInstance: eventInstance
        )
    }
}
#endif
