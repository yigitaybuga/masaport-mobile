import Foundation

struct CityRef: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
}

struct DistrictRef: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
    let cityId: Int?
}

struct DiscoveryCity: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let restaurantCount: Int
    let upcomingEventCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case restaurantCount = "restaurant_count"
        case upcomingEventCount = "upcoming_event_count"
    }

    var ref: CityRef { CityRef(id: id, name: name, slug: slug) }
}

struct DiscoveryDistrict: Codable, Hashable, Identifiable {
    let id: Int
    let cityId: Int
    let name: String
    let slug: String
    let restaurantCount: Int
    let upcomingEventCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case cityId = "city_id"
        case restaurantCount = "restaurant_count"
        case upcomingEventCount = "upcoming_event_count"
    }
}

struct DiscoveryLocations: Codable {
    let cities: [DiscoveryCity]
    let districts: [DiscoveryDistrict]
}

/// `/locations/reverse-geocode` ve `/locations/ip-lookup` cevabı.
struct LocationResolution: Codable, Hashable {
    let latitude: Double?
    let longitude: Double?
    let city: CityRef?
    let district: DistrictRef?
}
