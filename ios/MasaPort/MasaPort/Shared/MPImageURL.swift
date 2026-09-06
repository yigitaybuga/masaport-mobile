import Foundation

/// Semantic image usage mapped to the API's generated R2 siblings.
enum MPImageRole {
    case logo
    case thumbnail
    case card
    case detail
    case hero

    fileprivate var variant: String {
        switch self {
        case .logo, .thumbnail: "thumb"
        case .card: "card"
        case .detail, .hero: "hero"
        }
    }
}
enum MPImageURL {
    private static let r2Host = "cdn.masaport.com"
    private static let variants = ["thumb", "card", "hero"]

    /// Selects an R2 sibling only when the URL has the API variant shape.
    /// Legacy, external, local, and parameterized URLs are returned unchanged.
    static func variantURL(for url: URL?, role: MPImageRole) -> URL? {
        guard let url else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == r2Host,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return url }

        let path = components.path
        guard let current = variants.first(where: { path.hasSuffix("-\($0).webp") }) else {
            return url
        }
        let stem = String(path.dropLast("-\(current).webp".count))
        components.path = "\(stem)-\(role.variant).webp"
        return components.url ?? url
    }
}
