#if DEBUG
import Foundation

/// Yalnızca Debug derlemelerinde, `MASAPORT_DEMO=1` ortam değişkeni veya `-masaport-demo`
/// başlatma argümanıyla açılır. Ağ isteklerini bellek içi örnek verilerle yanıtlar.
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
    override class func canInit(with request: URLRequest) -> Bool {
        // Görseller gerçek ağdan gelsin; yalnızca API çağrıları taklit edilir.
        request.url?.host == AppConfiguration.apiBaseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Son isteğin Authorization başlığı; DemoStore hesap uçlarında oturumu buradan çözer.
    nonisolated(unsafe) static var currentAuthorization: String?

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.readBody(of: request)
        Self.currentAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let (statusCode, data) = DemoStore.shared.respond(method: request.httpMethod ?? "GET", url: url, body: body)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
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

// MARK: - Örnek veri

final class DemoStore {
    static let shared = DemoStore()

    private let lock = NSLock()
    private var nextReservationId = 4711
    private var reservedGuests: [Int: Int] = [:]
    /// Demo hesabı: kayıt kodu her zaman 123456, giriş için şifre "Demo1234".
    private var demoAccounts: [String: [String: Any]] = [:]
    private var demoSessionCounter = 0

    private let cities: [[String: Any]] = [
        ["id": 34, "name": "İstanbul", "slug": "istanbul", "restaurant_count": 6, "upcoming_event_count": 4, "event_count": 4, "restaurant_indexable": true, "event_indexable": true],
        ["id": 35, "name": "İzmir", "slug": "izmir", "restaurant_count": 2, "upcoming_event_count": 1, "event_count": 1, "restaurant_indexable": true, "event_indexable": false],
        ["id": 6, "name": "Ankara", "slug": "ankara", "restaurant_count": 1, "upcoming_event_count": 0, "event_count": 0, "restaurant_indexable": false, "event_indexable": false],
    ]

    private let districts: [[String: Any]] = [
        ["id": 1, "city_id": 34, "name": "Kadıköy", "slug": "kadikoy", "restaurant_count": 3, "upcoming_event_count": 2, "restaurant_indexable": true, "event_indexable": true],
        ["id": 2, "city_id": 34, "name": "Beşiktaş", "slug": "besiktas", "restaurant_count": 2, "upcoming_event_count": 1, "restaurant_indexable": true, "event_indexable": true],
        ["id": 3, "city_id": 34, "name": "Beyoğlu", "slug": "beyoglu", "restaurant_count": 1, "upcoming_event_count": 1, "restaurant_indexable": false, "event_indexable": true],
        ["id": 4, "city_id": 35, "name": "Alsancak", "slug": "alsancak", "restaurant_count": 2, "upcoming_event_count": 1, "restaurant_indexable": true, "event_indexable": false],
    ]

    private lazy var listings: [[String: Any]] = [
        listing(1, "Moda Balıkçısı", "moda-balikcisi", ["Balık", "Meze"], "Kadıköy", 1, 34, 4.8, "₺₺₺", 40.9789, 29.0263, 214, "photo-1544148103-0773bf10d330", "Moda sahilinde günlük balık ve klasik mezeler. Gün batımı masaları için erken rezervasyon önerilir.", ["Deniz manzarası", "Rakı-balık", "Canlı müzik"], 12, ["19:00", "19:30", "21:00"]),
        listing(2, "Kuzine Bahçe", "kuzine-bahce", ["Akdeniz", "Kahvaltı"], "Beşiktaş", 2, 34, 4.6, "₺₺", 41.0431, 29.0074, 87, "photo-1555396273-367ea4eb4db5", "Bahçe içinde odun fırını, serpme kahvaltı ve mevsim menüsü.", ["Bahçe", "Evcil hayvan dostu", "Serpme kahvaltı"], 6, ["12:30", "13:00"]),
        listing(3, "Nara Sushi", "nara-sushi", ["Japon", "Sushi"], "Beşiktaş", 2, 34, 4.7, "₺₺₺₺", 41.0500, 29.0100, 156, "photo-1579871494447-9811cf80d66c", "Omakase tezgahı ve şef seçkileri. Tezgah rezervasyonu sınırlı.", ["Omakase", "Şef tezgahı"], 9, ["20:00", "20:30", "22:00"]),
        listing(4, "Ocakbaşı Selim Usta", "ocakbasi-selim-usta", ["Kebap", "Ocakbaşı"], "Kadıköy", 1, 34, 4.5, "₺₺", 40.9900, 29.0300, 302, "photo-1529193591184-b1d58069ecdd", "Kömür ateşinde Adana ve Urfa, taş fırında lahmacun.", ["Ocakbaşı", "Aile dostu"], 18, ["18:30", "19:00", "19:30", "20:00"]),
        listing(5, "Verde", "verde", ["Vegan", "İtalyan"], "Kadıköy", 1, 34, 4.4, "₺₺", 40.9850, 29.0250, 64, "photo-1490645935967-10de6ba17061", "Taze makarna, bitki bazlı menü ve doğal şaraplar.", ["Vegan seçenekler", "Doğal şarap"], 4, ["19:30"]),
        listing(6, "Galata Meyhane", "galata-meyhane", ["Meze", "Meyhane"], "Beyoğlu", 3, 34, 4.3, "₺₺", 41.0256, 28.9744, 128, "photo-1414235077428-338989a2e8c0", "Galata Kulesi'ne yürüme mesafesinde klasik meyhane.", ["Canlı fasıl", "Tarihi bina"], 7, []),
        listing(7, "Kordon Levrek", "kordon-levrek", ["Balık", "Ege"], "Alsancak", 4, 35, 4.6, "₺₺₺", 38.4380, 27.1430, 91, "photo-1559339352-11d035aa65de", "Kordon boyunda deniz ürünleri ve Ege otları.", ["Deniz manzarası"], 5, ["19:00", "20:00"]),
        listing(8, "Alsancak Kahvaltı Evi", "alsancak-kahvalti-evi", ["Kahvaltı"], "Alsancak", 4, 35, 4.2, "₺", 38.4400, 27.1450, 45, "photo-1533089860892-a7c6f0a88666", "Köy kahvaltısı ve el yapımı reçeller.", ["Serpme kahvaltı"], 2, ["10:00", "10:30", "11:00"]),
        listing(9, "Tunalı Bistro", "tunali-bistro", ["Fransız", "Bistro"], "Çankaya", 5, 6, 4.5, "₺₺₺", 39.9000, 32.8600, 73, "photo-1517248135467-4c7edcad34c4", "Tunalı'da klasik bistro mutfağı.", ["Şarap listesi"], 3, ["19:00", "20:30"]),
    ]

    private func listing(_ id: Int, _ name: String, _ slug: String, _ cuisine: [String], _ districtName: String, _ districtId: Int, _ cityId: Int, _ rating: Double, _ price: String, _ lat: Double, _ lng: Double, _ reviews: Int, _ photo: String, _ description: String, _ features: [String], _ booked: Int, _ times: [String]) -> [String: Any] {
        let city = cities.first { ($0["id"] as? Int) == cityId }
        return [
            "id": id, "name": name, "slug": slug, "cuisine": cuisine, "location": "\(districtName), \(city?["name"] ?? "")", "neighborhood": districtName,
            "city": ["id": cityId, "name": city?["name"] ?? "", "slug": city?["slug"] ?? ""],
            "district": ["id": districtId, "name": districtName, "slug": districtName.lowercased(), "cityId": cityId],
            "rating": String(rating), "priceRange": price, "description": description,
            "image": "https://images.unsplash.com/\(photo)?w=1200&q=80",
            "coverImage": "https://images.unsplash.com/\(photo)?w=1200&q=80",
            "heroImage": "https://images.unsplash.com/\(photo)?w=1600&q=80",
            "gallery": ["https://images.unsplash.com/\(photo)?w=800&q=70", "https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?w=800&q=70", "https://images.unsplash.com/photo-1424847651672-bf20a4b0982b?w=800&q=70"],
            "features": features,
            "venue": ["id": id * 100, "name": name, "logo": NSNull(), "timezone": "Europe/Istanbul", "defaultReservationDurationMinutes": 90, "phone": "+90 216 555 00 \(String(format: "%02d", id))", "address": "\(districtName) Mah. Sahil Cad. No: \(id * 3), \(city?["name"] ?? "")", "cityId": cityId, "districtId": districtId, "latitude": String(lat), "longitude": String(lng)],
            "latitude": String(lat), "longitude": String(lng),
            "sectors": [["id": 1, "name": "Restoranlar", "description": NSNull(), "emoji": "🍽️", "iconUrl": NSNull()]],
            "bookedTodayCount": booked, "isReservationActive": true,
            "contactPhone": "+90 216 555 00 \(String(format: "%02d", id))", "contactEmail": "\(slug)@example.com", "contactAddress": "\(districtName) Mah. Sahil Cad. No: \(id * 3)",
            "workingHours": ["monday": ["open": "12:00", "close": "23:00", "closed": false], "tuesday": ["open": "12:00", "close": "23:00", "closed": false], "wednesday": ["open": "12:00", "close": "23:00", "closed": false], "thursday": ["open": "12:00", "close": "00:00", "closed": false], "friday": ["open": "12:00", "close": "01:00", "closed": false], "saturday": ["open": "10:00", "close": "01:00", "closed": false], "sunday": ["open": "10:00", "close": "22:00", "closed": id % 3 == 0]],
            "reviews": [
                ["id": id * 10 + 1, "userName": "A**** K.", "rating": 5, "comment": "Servis hızlı, lezzet mükemmeldi. Manzara masaları için önceden arayın.", "date": "2026-08-20T18:00:00.000Z"],
                ["id": id * 10 + 2, "userName": "M***t D.", "rating": 4, "comment": "Fiyatlar biraz yüksek ama kalite karşılıyor.", "date": "2026-08-12T18:00:00.000Z"],
            ],
            "reviewStats": ["averageRating": rating, "totalReviews": reviews, "ratingDistribution": ["5": reviews / 2, "4": reviews / 3, "3": reviews / 8, "2": 2, "1": 1]],
            "_times": times,
        ]
    }

    private lazy var events: [[String: Any]] = {
        let calendar = Calendar.istanbul
        func at(daysFromNow: Int, hour: Int) -> Date {
            var components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: daysFromNow, to: .now)!)
            components.hour = hour
            return calendar.date(from: components)!
        }
        let iso = ISO8601DateFormatter()
        func event(_ id: Int, _ title: String, _ category: (Int, String, String), _ cityId: Int, _ districtId: Int, _ venueId: Int?, _ venueName: String, _ price: Double?, _ capacity: Int?, _ photo: String, _ days: [Int], _ hour: Int, _ ticket: String?) -> [String: Any] {
            let city = cities.first { ($0["id"] as? Int) == cityId }
            let district = districts.first { ($0["id"] as? Int) == districtId }
            let instances: [[String: Any]] = days.enumerated().map { index, day in
                let start = at(daysFromNow: day, hour: hour)
                let reserved = capacity.map { max(0, $0 - (index == 0 ? 6 : 40)) } ?? 12
                return ["id": id * 10 + index, "eventId": id, "start_datetime": iso.string(from: start), "end_datetime": iso.string(from: start.addingTimeInterval(3 * 3600)), "total_reserved": reserved, "available_spots": capacity.map { $0 - reserved } ?? NSNull(), "max_capacity": capacity ?? NSNull()]
            }
            return [
                "id": id, "slug": title.lowercased().replacingOccurrences(of: " ", with: "-"), "title": title,
                "description": "\(title) — \(venueName) sahnesinde. Kapılar etkinlikten bir saat önce açılır; yer numarası yoktur, erken gelen iyi yer kapar.",
                "imageUrl": "https://images.unsplash.com/\(photo)?w=1200&q=80",
                "pricePerPerson": price.map { String($0) } ?? NSNull(), "paymentType": price == nil ? "NONE" : "FULL", "isRecurring": days.count > 1,
                "startDatetime": instances.first?["start_datetime"] ?? "", "endDatetime": instances.first?["end_datetime"] ?? "",
                "maxCapacity": capacity ?? NSNull(), "isPublishedToPublic": true,
                "category": ["id": category.0, "name": category.1, "slug": category.2],
                "venue": venueId.map { ["id": $0, "name": venueName, "address": "\(district?["name"] ?? "") Mah. Sanat Sok. No: \(id)", "logo": NSNull(), "phone": "+90 212 555 11 \(String(format: "%02d", id))"] } ?? NSNull(),
                "location": ["mode": venueId == nil ? "CUSTOM" : "VENUE", "name": venueName, "address": "\(district?["name"] ?? "") Mah. Sanat Sok. No: \(id)", "neighborhood": district?["name"] ?? "", "city": ["id": cityId, "name": city?["name"] ?? "", "slug": city?["slug"] ?? ""], "district": ["id": districtId, "name": district?["name"] ?? "", "slug": district?["slug"] ?? "", "cityId": cityId], "latitude": 41.02 + Double(id) * 0.004, "longitude": 28.98 + Double(id) * 0.006],
                "ticket_url": ticket ?? NSNull(),
                "instances": instances,
            ]
        }
        return [
            event(101, "Caz Gecesi: Moda Trio", (1, "Konser", "konser"), 34, 1, 100, "Moda Balıkçısı", 450, 60, "photo-1511192336575-5a79af67a629", [0, 7], 21, nil),
            event(102, "Şef Masası: Omakase Akşamı", (2, "Gastronomi", "gastronomi"), 34, 2, 300, "Nara Sushi", 1800, 12, "photo-1553621042-f6e147245754", [2], 20, nil),
            event(103, "Boğaz'da Açık Hava Sineması", (3, "Sinema", "sinema"), 34, 2, nil, "Beşiktaş Sahil Parkı", nil, 200, "photo-1478720568477-152d9b164e26", [1, 2, 3], 21, nil),
            event(104, "Stand-up: Cuma Kahkahası", (4, "Sahne", "sahne"), 34, 3, nil, "Galata Sahne", 350, nil, "photo-1527224857830-43a7acc85260", [4], 20, "https://www.example-bilet.com/cuma-kahkahasi"),
            event(105, "Kordon Şarap Tadımı", (2, "Gastronomi", "gastronomi"), 35, 4, 700, "Kordon Levrek", 900, 24, "photo-1510812431401-41d2bd2722f3", [5], 19, nil),
        ]
    }()

    // MARK: Yönlendirme

    func respond(method: String, url: URL, body: Data) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        let path = url.path.replacingOccurrences(of: "/api", with: "", options: .anchored)
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let segments = path.split(separator: "/").map(String.init)

        let route = "\(method) " + segments.joined(separator: "/")
        switch route {
        case "GET public/discovery/feed":
            return ok(feed(surface: query["surface"] ?? "homepage", cityId: Int(query["city_id"] ?? "")))
        case "GET public/discovery/locations":
            return ok(["cities": cities, "districts": districts, "thresholds": ["min_restaurants": 5, "min_upcoming_events": 3]])
        case "GET locations/reverse-geocode", "GET locations/ip-lookup":
            return ok(["latitude": 40.98, "longitude": 29.03, "city": cities[0].picking(["id", "name", "slug"]), "district": ["id": 1, "cityId": 34, "name": "Kadıköy", "slug": "kadikoy"]])
        case "GET public/listings":
            return ok(listingsResponse(query))
        case "GET public/listings/filters":
            return ok(["default_date": DateFormat.apiDay.string(from: .now), "default_time": "19:30", "default_guest_count": 2, "locations": ["Kadıköy", "Beşiktaş", "Beyoğlu"], "time_options": stride(from: 11, through: 23, by: 1).flatMap { ["\(String(format: "%02d", $0)):00", "\(String(format: "%02d", $0)):30"] }, "guest_count_options": Array(1...12), "max_guest_capacity": 12, "total_listings": listings.count])
        case "GET public/events":
            return ok(eventsResponse(query))
        case "GET public/event-categories":
            return ok([["id": 1, "name": "Konser", "slug": "konser"], ["id": 2, "name": "Gastronomi", "slug": "gastronomi"], ["id": 3, "name": "Sinema", "slug": "sinema"], ["id": 4, "name": "Sahne", "slug": "sahne"]])
        case "POST reservations":
            return createReservation(body: body)
        case "GET payments/config":
            return fail(503, "Payment provider is not configured")
        case "POST customer/auth/register":
            let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let email = (payload["email"] as? String ?? "").lowercased()
            if demoAccounts[email] != nil { return fail(409, "Bu e-posta ile zaten bir hesap var.", code: "EMAIL_ALREADY_REGISTERED") }
            demoAccounts["pending:" + email] = ["name": payload["name"] ?? "Misafir", "phone": payload["phone"] ?? NSNull(), "password": payload["password"] ?? ""]
            return ok(["email": email, "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(900)), "resendAvailableAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60)), "debug_code": "123456"])
        case "POST customer/auth/register/resend":
            return ok(["email": "", "resendAvailableAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60)), "debug_code": "123456"])
        case "POST customer/auth/register/verify":
            let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let email = (payload["email"] as? String ?? "").lowercased()
            guard let pending = demoAccounts["pending:" + email] else { return fail(404, "Bekleyen kayıt yok.", code: "VERIFICATION_NOT_FOUND") }
            guard (payload["code"] as? String) == "123456" else { return fail(400, "Kod hatalı.", code: "OTP_INVALID") }
            demoAccounts[email] = ["id": demoAccounts.count + 1, "name": pending["name"] ?? "Misafir", "email": email, "phone": pending["phone"] ?? NSNull(), "password": pending["password"] ?? "", "email_verified": true, "marketing_consent": false]
            demoAccounts.removeValue(forKey: "pending:" + email)
            return ok(demoSession(for: email), status: 201)
        case "POST customer/auth/login":
            let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let email = (payload["email"] as? String ?? "").lowercased()
            if demoAccounts[email] == nil, email == "demo@masaport.com" {
                demoAccounts[email] = ["id": 1, "name": "Demo Misafir", "email": email, "phone": "+905551112233", "password": "Demo1234", "email_verified": true, "marketing_consent": false]
            }
            guard let account = demoAccounts[email], (account["password"] as? String) == (payload["password"] as? String) else {
                return fail(401, "E-posta veya şifre hatalı.", code: "INVALID_CREDENTIALS")
            }
            return ok(demoSession(for: email))
        case "POST customer/auth/refresh":
            let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let token = payload["refresh_token"] as? String ?? ""
            guard let email = demoAccounts.first(where: { ($0.value["refresh"] as? String) == token })?.key else {
                return fail(401, "Oturumun sona erdi.", code: "CUSTOMER_SESSION_EXPIRED")
            }
            return ok(demoSession(for: email))
        case "POST customer/auth/logout":
            return ok(["revoked": true])
        case "POST customer/auth/forgot-password":
            return (200, (try? JSONSerialization.data(withJSONObject: ["success": true, "data": NSNull(), "message": "Bu e-posta ile bir hesap varsa şifre sıfırlama bağlantısını gönderdik."])) ?? Data())
        case "GET customer/auth/me", "PATCH customer/auth/me", "DELETE customer/auth/me":
            guard let email = demoAuthenticatedEmail(url: url) else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            if method == "DELETE" {
                let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                guard (demoAccounts[email]?["password"] as? String) == (payload["password"] as? String) else { return fail(400, "Şifren hatalı.", code: "CURRENT_PASSWORD_INVALID") }
                demoAccounts.removeValue(forKey: email)
                return ok(["deleted": true])
            }
            if method == "PATCH", let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                var account = demoAccounts[email] ?? [:]
                if let name = payload["name"] as? String { account["name"] = name }
                if let phone = payload["phone"] as? String { account["phone"] = phone.isEmpty ? NSNull() : phone }
                if let consent = payload["marketing_consent"] as? Bool { account["marketing_consent"] = consent }
                if let birth = payload["birth_date"] as? String { account["birth_date"] = birth.isEmpty ? NSNull() : birth }
                if let preferences = payload["preferences"] as? [String: Any] {
                    var current = account["preferences"] as? [String: Any] ?? [:]
                    for key in ["dietary", "seating"] {
                        if let list = preferences[key] as? [String] { current[key] = list }
                    }
                    account["preferences"] = current
                }
                demoAccounts[email] = account
            }
            return ok(["account": demoAccountPayload(email)])
        case "GET customer/auth/sessions":
            guard demoAuthenticatedEmail(url: url) != nil else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            let now = ISO8601DateFormatter().string(from: .now)
            let earlier = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 3600))
            return ok(["sessions": [
                ["id": "demo-current", "device": "MasaPort iOS uygulaması", "platform": "ios", "is_current": true, "created_at": now, "last_used_at": now, "expires_at": now],
                ["id": "demo-mac", "device": "Chrome · Mac", "platform": "desktop", "is_current": false, "created_at": earlier, "last_used_at": earlier, "expires_at": now],
            ]])
        case "POST customer/auth/sessions/revoke-others":
            guard demoAuthenticatedEmail(url: url) != nil else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            return ok(["revoked": true])
        case "POST customer/auth/change-password":
            guard let email = demoAuthenticatedEmail(url: url), let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            guard (demoAccounts[email]?["password"] as? String) == (payload["current_password"] as? String) else { return fail(400, "Mevcut şifren hatalı.", code: "CURRENT_PASSWORD_INVALID") }
            demoAccounts[email]?["password"] = payload["new_password"] ?? ""
            return ok(["changed": true])
        case "GET customer/reservations":
            guard demoAuthenticatedEmail(url: url) != nil else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            let tomorrow = Calendar.istanbul.date(byAdding: .day, value: 2, to: .now) ?? .now
            return ok(["reservations": [[
                "kind": "restaurant", "id": 9001, "uuid": UUID().uuidString.lowercased(), "status": "CONFIRMED",
                "reservation_date": DateFormat.apiDay.string(from: tomorrow), "start_time": "20:00", "end_time": "22:00",
                "guest_count": 4, "note": NSNull(), "checked_in": false, "source": "masaport_web", "created_at": ISO8601DateFormatter().string(from: .now),
                "customer_name": "Demo Misafir",
                "venue": ["id": 100, "name": "Moda Balıkçısı", "logo": NSNull(), "address": "Moda Cad. No: 12, Kadıköy", "phone": "+90 216 555 00 01", "timezone": "Europe/Istanbul", "latitude": 40.9789, "longitude": 29.0263, "listing_slug": "moda-balikcisi", "image": "https://images.unsplash.com/photo-1544148103-0773bf10d330?w=1200&q=80"],
            ]]])
        default:
            break
        }

        if method == "DELETE", segments.count == 4, segments[0] == "customer", segments[1] == "auth", segments[2] == "sessions" {
            guard demoAuthenticatedEmail(url: url) != nil else { return fail(401, "Giriş yapman gerekiyor.", code: "CUSTOMER_AUTH_REQUIRED") }
            return ok(["revoked": true, "was_current": segments[3] == "demo-current"])
        }
        if method == "GET", segments.count == 3, segments[0] == "public", segments[1] == "restaurants" {
            guard let item = listings.first(where: { ($0["slug"] as? String) == segments[2] }) else { return fail(404, "Venue not found") }
            let detail = item.filter { $0.key != "_times" }
            return ok(["listing": detail, "restaurant": detail])
        }
        if method == "GET", segments.count == 3, segments[0] == "venues", segments[1] == "public" {
            guard let id = Int(segments[2]), let item = listings.first(where: { (($0["venue"] as? [String: Any])?["id"] as? Int) == id }) else { return fail(404, "Venue not found") }
            return ok(availability(for: item, query: query))
        }
        if method == "GET", segments.count == 3, segments[0] == "events", segments[2] == "public" {
            guard let id = Int(segments[1]), let item = events.first(where: { ($0["id"] as? Int) == id }) else { return fail(404, "Event not found") }
            return ok(item)
        }
        if method == "POST", segments.count == 5, segments[0] == "events", segments[2] == "instances", segments[4] == "reservations" {
            return createEventReservation(eventId: Int(segments[1]) ?? 0, instanceId: Int(segments[3]) ?? 0, body: body)
        }
        return fail(404, "Not found: \(path)")
    }

    // MARK: Yanıt oluşturucular

    private func feed(surface: String, cityId: Int?) -> [String: Any] {
        let pool = listings.filter { cityId == nil || (($0["city"] as? [String: Any])?["id"] as? Int) == cityId }
        func card(_ item: [String: Any]) -> [String: Any] {
            ["id": item["id"]!, "name": item["name"]!, "slug": item["slug"]!, "cuisine": item["cuisine"]!, "location": item["location"]!, "rating": Double(item["rating"] as? String ?? "0") ?? 0, "priceRange": item["priceRange"]!, "image": item["image"]!, "city": item["city"]!]
        }
        if surface == "events" {
            let eventPool = events.filter { cityId == nil || ((($0["location"] as? [String: Any])?["city"] as? [String: Any])?["id"] as? Int) == cityId }
            let cards: [[String: Any]] = eventPool.map { item in
                ["id": item["id"]!, "slug": item["slug"]!, "title": item["title"]!, "image_url": item["imageUrl"]!, "price_per_person": (item["pricePerPerson"] as? String).flatMap(Double.init) ?? NSNull(), "ticket_url": item["ticket_url"]!, "start_datetime": item["startDatetime"]!, "created_at": NSNull(), "venue_name": (item["location"] as? [String: Any])?["name"] ?? "", "city": (item["location"] as? [String: Any])?["city"] ?? NSNull(), "district": (item["location"] as? [String: Any])?["district"] ?? NSNull(), "category": item["category"]!, "is_tonight": false, "is_weekend": false]
            }
            return ["surface": "events", "city_id": cityId ?? NSNull(), "rotation_bucket": 1234, "modules": [["key": "events_showcase", "title": "Yaklaşan etkinlikler", "subtitle": NSNull(), "description": NSNull(), "cta_label": NSNull(), "cta_href": NSNull(), "layout": "event-cards", "selection_reason": "upcoming_14d", "pinned": [], "candidates": cards]]]
        }
        let seaside = pool.filter { ($0["cuisine"] as? [String])?.contains("Balık") == true }.compactMap { $0["id"] as? Int }
        let breakfast = pool.filter { ($0["cuisine"] as? [String])?.contains("Kahvaltı") == true }.compactMap { $0["id"] as? Int }
        let collections: [[String: Any]] = [
            ["id": 1, "title": "Deniz kenarında akşam", "description": "Gün batımı manzaralı masalar", "image": "https://images.unsplash.com/photo-1519046904884-53103b34b206?w=1200&q=80", "href": NSNull(), "listing_ids": seaside],
            ["id": 2, "title": "Hafta sonu kahvaltısı", "description": "Serpme ve köy kahvaltıları", "image": "https://images.unsplash.com/photo-1493770348161-369560ae357d?w=1200&q=80", "href": NSNull(), "listing_ids": breakfast],
            ["id": 3, "title": "Şef tezgahları", "description": "Omakase ve tadım menüleri", "image": "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=1200&q=80", "href": NSNull(), "listing_ids": pool.filter { ($0["priceRange"] as? String) == "₺₺₺₺" }.compactMap { $0["id"] as? Int }],
        ]
        let cuisines: [[String: Any]] = ["Balık", "Kebap", "Kahvaltı", "Japon", "Vegan", "Meze"].enumerated().map { index, name in
            ["id": 100 + index, "title": name, "description": NSNull(), "image": "https://images.unsplash.com/photo-\(["1544148103-0773bf10d330", "1529193591184-b1d58069ecdd", "1533089860892-a7c6f0a88666", "1579871494447-9811cf80d66c", "1490645935967-10de6ba17061", "1414235077428-338989a2e8c0"][index])?w=400&q=70", "href": NSNull(), "listing_ids": pool.filter { ($0["cuisine"] as? [String])?.contains(name) == true }.compactMap { $0["id"] as? Int }]
        }
        return ["surface": "homepage", "city_id": cityId ?? NSNull(), "rotation_bucket": 1234, "modules": [
            ["key": "featured_collections", "title": "Seçkiler", "subtitle": NSNull(), "description": NSNull(), "cta_label": NSNull(), "cta_href": NSNull(), "layout": "collection-cards", "selection_reason": "curated_rotation", "pinned": [], "candidates": collections.filter { !(($0["listing_ids"] as? [Int]) ?? []).isEmpty }],
            ["key": "cuisine_explorer", "title": "Mutfağa göre", "subtitle": NSNull(), "description": NSNull(), "cta_label": NSNull(), "cta_href": NSNull(), "layout": "content-cards", "selection_reason": "curated_rotation", "pinned": [], "candidates": cuisines.filter { !(($0["listing_ids"] as? [Int]) ?? []).isEmpty }],
            ["key": "popular_restaurants", "title": "Popüler restoranlar", "subtitle": "Bu hafta en çok rezervasyon alanlar", "description": NSNull(), "cta_label": NSNull(), "cta_href": NSNull(), "layout": "listing-cards", "selection_reason": "top_rated_rotation", "pinned": pool.prefix(1).map(card), "candidates": pool.dropFirst().map(card)],
        ]]
    }

    private func listingsResponse(_ query: [String: String]) -> [String: Any] {
        var items = listings
        if let ids = query["listingIds"]?.split(separator: ",").compactMap({ Int($0) }), !ids.isEmpty {
            items = items.filter { ids.contains($0["id"] as? Int ?? 0) }
        }
        if let cityId = Int(query["city_id"] ?? "") {
            items = items.filter { (($0["city"] as? [String: Any])?["id"] as? Int) == cityId }
        }
        if let districtId = Int(query["district_id"] ?? "") {
            items = items.filter { (($0["district"] as? [String: Any])?["id"] as? Int) == districtId }
        }
        if let term = query["query"]?.lowercased(), !term.isEmpty {
            items = items.filter { item in
                let haystack = [(item["name"] as? String) ?? "", (item["location"] as? String) ?? ""] + ((item["cuisine"] as? [String]) ?? [])
                return haystack.contains { $0.lowercased(with: Locale(identifier: "tr")).contains(term) }
            }
        }
        let hasAvailability = query["date"] != nil || query["start_time"] != nil || query["guestCount"] != nil
        let hasGeo = query["lat"] != nil && query["lng"] != nil
        var formatted: [[String: Any]] = items.compactMap { item in
            var card = item
            for key in ["coverImage", "heroImage", "gallery", "contactPhone", "contactEmail", "contactAddress", "workingHours", "reviews", "reviewStats"] { card.removeValue(forKey: key) }
            let times = (item["_times"] as? [String]) ?? []
            card.removeValue(forKey: "_times")
            if hasAvailability {
                if times.isEmpty { return nil }
                var available = times
                if let start = query["start_time"] {
                    available = times.filter { $0 >= start }
                    if available.isEmpty { return nil }
                    card["discoveryMatchedTime"] = available.first!
                }
                card["discoveryAvailableTimes"] = Array(available.prefix(4))
            }
            if hasGeo, let lat = Double(query["lat"] ?? ""), let lng = Double(query["lng"] ?? ""), let ilat = Double(item["latitude"] as? String ?? ""), let ilng = Double(item["longitude"] as? String ?? "") {
                let distance = (pow(ilat - lat, 2) + pow((ilng - lng) * 0.75, 2)).squareRoot() * 111
                if distance > (Double(query["radius"] ?? "25") ?? 25) { return nil }
                card["distance"] = (distance * 10).rounded() / 10
            }
            return card
        }
        switch query["orderBy"] {
        case "name": formatted.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        case "distance": formatted.sort { ($0["distance"] as? Double ?? 0) < ($1["distance"] as? Double ?? 0) }
        default: formatted.sort { (Double($0["rating"] as? String ?? "0") ?? 0) > (Double($1["rating"] as? String ?? "0") ?? 0) }
        }
        let limit = Int(query["limit"] ?? "20") ?? 20
        let offset = Int(query["offset"] ?? "0") ?? 0
        let page = Array(formatted.dropFirst(offset).prefix(limit))
        return ["listings": page, "restaurants": page, "pagination": ["total": formatted.count, "limit": limit, "offset": offset, "hasMore": offset + limit < formatted.count, "currentPage": offset / max(limit, 1) + 1, "totalPages": max(1, (formatted.count + limit - 1) / limit)]]
    }

    private func availability(for item: [String: Any], query: [String: String]) -> [String: Any] {
        let venue = item["venue"] as? [String: Any] ?? [:]
        let times = (item["_times"] as? [String]) ?? ["19:00", "20:00"]
        let base = ["12:00", "12:30", "13:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "22:00"]
        let allTimes = Array(Set(base + times)).sorted()
        func slot(_ index: Int, _ time: String) -> [String: Any] {
            let hour = Int(time.prefix(2)) ?? 19
            return ["id": (venue["id"] as? Int ?? 0) * 10 + index, "start_time": time, "end_time": String(format: "%02d:%@", (hour + 2) % 24, time.suffix(2) as CVarArg), "duration_minutes": 120, "uses_venue_default_duration": true, "is_end_time_derived": true, "minimum_duration_minutes": NSNull(), "is_minimum_duration_applied": false, "max_reservations_in_slot": 10, "max_guests_in_slot": 40, "booking_mode": time == "22:00" ? "REQUEST_ONLY" : "STANDARD", "requires_manual_approval": time == "22:00", "booking_message": time == "22:00" ? "Geç saat rezervasyonları mekan onayıyla kesinleşir." : NSNull(), "minimum_spend_required": false, "minimum_spend_amount": 0, "minimum_spend_summary": NSNull(), "prepayment_required": time == "20:30" && (item["priceRange"] as? String) == "₺₺₺₺", "prepayment_mode": "DEFAULT", "prepayment_amount": 0, "prepayment_total_amount": 0, "prepayment_summary": time == "20:30" && (item["priceRange"] as? String) == "₺₺₺₺" ? "Kişi başı 500 ₺ ön ödeme alınır." : NSNull(), "effective_rule_id": NSNull(), "effective_rule_name": NSNull(), "pacing_interval_minutes": NSNull(), "max_pacing_reservations_per_interval": NSNull(), "max_pacing_guests_per_interval": NSNull()]
        }
        let daySlots = allTimes.enumerated().map { slot($0.offset, $0.element) }
        var slotsByDay: [String: Any] = [:]
        for day in 1...7 { slotsByDay[String(day)] = daySlots }
        let startDate = query["startDate"] ?? query["date"] ?? DateFormat.apiDay.string(from: .now)
        var slotStatus: [String: Any] = [:]
        for s in daySlots {
            let time = s["start_time"] as? String ?? ""
            let full = !times.contains(time) && Int(time.prefix(2)).map { $0 >= 18 } == true
            slotStatus[String(s["id"] as? Int ?? 0)] = ["is_full": full, "is_blocked": false, "is_blocked_by_time": false, "available_guest_capacity": full ? 0 : 12, "available_tables": full ? 0 : 3]
        }
        return ["id": venue["id"] ?? 0, "name": venue["name"] ?? "", "timezone": "Europe/Istanbul", "texts": [["id": 1, "title": "KVKK Aydınlatma Metni", "type": "kvkk", "content": "Rezervasyon sürecinde paylaştığınız ad, telefon ve e-posta bilgileri yalnızca rezervasyonunuzu yönetmek ve sizi bilgilendirmek amacıyla işlenir; üçüncü taraflarla paylaşılmaz."]], "slots": slotsByDay, "blocked_dates": [], "availability": [startDate: ["is_blocked": false, "is_day_full": false, "slots": slotStatus]], "isSubscriptionActive": true]
    }

    private func createReservation(body: Data) -> (Int, Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let slotId = payload["time_slot_id"] as? Int, let venueId = payload["venue_id"] as? Int else {
            return fail(400, "Validation failed")
        }
        guard let item = listings.first(where: { (($0["venue"] as? [String: Any])?["id"] as? Int) == venueId }) else { return fail(404, "Venue not found") }
        let times = Array(Set((["12:00", "12:30", "13:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "22:00"]) + ((item["_times"] as? [String]) ?? []))).sorted()
        let index = slotId - venueId * 10
        guard times.indices.contains(index) else { return fail(400, "Invalid time slot") }
        let time = times[index]
        if (payload["customer_name"] as? String)?.lowercased().contains("dolu") == true {
            return fail(409, "Seçilen tarih ve saat aralığında yeterli masa bulunamadı. Lütfen başka bir saat deneyin.")
        }
        nextReservationId += 1
        let pending = time == "22:00"
        return ok(["success": true, "message": "Reservation created successfully", "data": ["reservation_id": nextReservationId, "reservation_uuid": UUID().uuidString.lowercased(), "reservation_status": pending ? "PENDING" : "CONFIRMED", "table_ids": [3], "start_time": time, "end_time": String(format: "%02d:%@", ((Int(time.prefix(2)) ?? 19) + 2) % 24, time.suffix(2) as CVarArg), "requires_manual_approval": pending, "booking_mode": pending ? "REQUEST_ONLY" : "STANDARD", "booking_message": pending ? "Mekan en geç 2 saat içinde onaylayacak." : NSNull(), "requires_payment": false, "amount": 0, "minimum_spend_required": false, "minimum_spend_amount": 0, "minimum_spend_summary": NSNull(), "minimum_duration_minutes": NSNull(), "prepayment_mode": "DEFAULT", "prepayment_summary": NSNull()]], status: 201)
    }

    private func eventsResponse(_ query: [String: String]) -> [String: Any] {
        var items = events
        if let cityId = Int(query["city_id"] ?? "") {
            items = items.filter { ((($0["location"] as? [String: Any])?["city"] as? [String: Any])?["id"] as? Int) == cityId }
        }
        if let categoryId = Int(query["category_id"] ?? "") {
            items = items.filter { (($0["category"] as? [String: Any])?["id"] as? Int) == categoryId }
        }
        if let term = query["search"]?.lowercased(), !term.isEmpty {
            items = items.filter { (($0["title"] as? String) ?? "").lowercased(with: Locale(identifier: "tr")).contains(term) }
        }
        let start = query["start_date"], end = query["end_date"]
        let formatted: [[String: Any]] = items.compactMap { item in
            let instances = (item["instances"] as? [[String: Any]]) ?? []
            let inRange = instances.filter { instance in
                let day = String((instance["start_datetime"] as? String ?? "").prefix(10))
                if let start, day < start { return false }
                if let end, day > end { return false }
                return true
            }
            guard let next = inRange.first else { return nil }
            let location = item["location"] as? [String: Any] ?? [:]
            return ["id": item["id"]!, "slug": item["slug"]!, "title": item["title"]!, "description": item["description"]!, "image_url": item["imageUrl"]!, "price_per_person": (item["pricePerPerson"] as? String).flatMap(Double.init) ?? NSNull(), "payment_type": item["paymentType"]!, "is_recurring": item["isRecurring"]!, "start_datetime": item["startDatetime"]!, "end_datetime": item["endDatetime"]!, "max_capacity": item["maxCapacity"]!, "is_published_to_public": true, "category": item["category"]!, "location": location, "ticket_url": item["ticket_url"]!, "venue": item["venue"]!, "next_instance": next]
        }
        return ["events": formatted, "pagination": ["page": 1, "per_page": 24, "total": formatted.count, "total_pages": 1]]
    }

    private func createEventReservation(eventId: Int, instanceId: Int, body: Data) -> (Int, Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let name = payload["contact_name"] as? String, !name.isEmpty else {
            return fail(400, "Contact name is required")
        }
        guard let event = events.first(where: { ($0["id"] as? Int) == eventId }) else { return fail(404, "Event not found") }
        let guests = payload["guest_count"] as? Int ?? 1
        if let capacity = event["maxCapacity"] as? Int, (reservedGuests[instanceId] ?? 0) + guests > capacity {
            return fail(409, "Etkinlik için ayrılan kontenjan doldu")
        }
        reservedGuests[instanceId, default: 0] += guests
        nextReservationId += 1
        return ok(["success": true, "message": "Event reservation created successfully", "data": ["id": nextReservationId, "uuid": UUID().uuidString.lowercased(), "eventInstanceId": instanceId, "contactName": name, "contactEmail": payload["contact_email"] ?? NSNull(), "contactPhone": payload["contact_phone"] ?? NSNull(), "note": payload["notes"] ?? NSNull(), "guestCount": guests, "paymentStatus": "PAID", "totalAmount": "0", "originalAmount": "0", "discountAmount": "0", "checkedIn": false, "createdAt": ISO8601DateFormatter().string(from: .now)]])
    }

    // MARK: Demo hesap yardımcıları

    private func demoSession(for email: String) -> [String: Any] {
        demoSessionCounter += 1
        let refresh = "demo-refresh-\(demoSessionCounter)-" + String(repeating: "x", count: 40)
        demoAccounts[email]?["refresh"] = refresh
        // Erişim token'ı e-postayı taşır; DemoURLProtocol Authorization başlığından çözer.
        let access = "demo-access." + Data(email.utf8).base64EncodedString()
        return ["access_token": access, "refresh_token": refresh, "token_type": "Bearer", "expires_in": 900, "session": ["id": "demo", "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))], "account": demoAccountPayload(email)]
    }

    private func demoAccountPayload(_ email: String) -> [String: Any] {
        let account = demoAccounts[email] ?? [:]
        return [
            "id": account["id"] ?? 1, "name": account["name"] ?? "Misafir", "email": email, "phone": account["phone"] ?? NSNull(),
            "email_verified": true, "marketing_consent": account["marketing_consent"] ?? false,
            "birth_date": account["birth_date"] ?? NSNull(), "preferences": account["preferences"] ?? ["dietary": [], "seating": []],
            "created_at": "2026-06-01T10:00:00.000Z",
        ]
    }

    private func demoAuthenticatedEmail(url: URL) -> String? {
        guard let header = DemoURLProtocol.currentAuthorization, header.hasPrefix("Bearer demo-access.") else { return nil }
        let encoded = String(header.dropFirst("Bearer demo-access.".count))
        guard let data = Data(base64Encoded: encoded), let email = String(data: data, encoding: .utf8), demoAccounts[email] != nil else { return nil }
        return email
    }

    // MARK: Yardımcılar

    private func ok(_ data: Any, status: Int = 200) -> (Int, Data) {
        let envelope: [String: Any] = ["success": true, "data": data]
        return (status, (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data())
    }

    private func fail(_ status: Int, _ message: String, code: String = "DEMO_ERROR") -> (Int, Data) {
        let envelope: [String: Any] = ["success": false, "data": NSNull(), "error": message, "message": message, "code": code]
        return (status, (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data())
    }
}

private extension Dictionary where Key == String, Value == Any {
    func picking(_ keys: [String]) -> [String: Any] {
        filter { keys.contains($0.key) }
    }
}
#endif
