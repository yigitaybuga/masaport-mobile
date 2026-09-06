import Foundation

enum VenueRole: String, Codable, CaseIterable {
    case superAdmin = "super_admin"
    case venueOwner = "venue_owner"
    case manager
    case staff
    case accounting
    case host

    var canUseOperationsApp: Bool { self != .accounting }
}

struct VenueRoleAssignment: Codable, Identifiable, Hashable {
    let venueId: Int
    let role: VenueRole

    var id: Int { venueId }
}

struct OperationUser: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String
    let venueRoles: [VenueRoleAssignment]

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case venueRoles = "venue_roles"
    }
}

struct Venue: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let timezone: String?
    let logo: String?
}

struct MobileAuthPayload: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let session: MobileSession
    let user: OperationUser
    let venues: [Venue]

    enum CodingKeys: String, CodingKey {
        case user, venues, session
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct MobileSession: Codable {
    let id: String
    let expiresAt: String
    let installationID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case expiresAt = "expires_at"
        case installationID = "installation_id"
    }
}

struct MobileCurrentUserPayload: Codable {
    let user: OperationUser
    let venues: [Venue]
}

struct MobileLoginRequest: Encodable {
    let email: String
    let password: String
    let installationID: String
    let platform = "ios"
    let deviceName: String
    let appVersion: String
    let buildNumber: String

    enum CodingKeys: String, CodingKey {
        case email, password, platform
        case installationID = "installation_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
    }
}

struct MobileRefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
