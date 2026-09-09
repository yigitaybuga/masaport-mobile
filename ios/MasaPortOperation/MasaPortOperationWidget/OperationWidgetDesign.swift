import SwiftUI

enum OperationWidgetDesign {
    /// Uygulama ile aynı marka rengi: ikondaki lacivert/slate, koyu modda açık çelik.
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.80, blue: 0.89, alpha: 1)
            : UIColor(red: 0.176, green: 0.216, blue: 0.282, alpha: 1)
    })

    // Hero yüzey: uygulamadaki Bugün başlığıyla aynı lacivert geçiş.
    static let navySoft = Color(red: 0.290, green: 0.337, blue: 0.408)
    static let navy = Color(red: 0.176, green: 0.216, blue: 0.282)
    static let navyDeep = Color(red: 0.106, green: 0.129, blue: 0.176)
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [navySoft, navy, navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let onHero = Color.white
    static let onHeroSecondary = Color.white.opacity(0.72)
    static let heroFill = Color.white.opacity(0.12)
    static let heroPositive = Color(red: 0.42, green: 0.86, blue: 0.58)
    static let heroAttention = Color(red: 1.0, green: 0.72, blue: 0.36)
    static let heroCritical = Color(red: 1.0, green: 0.48, blue: 0.45)

    static let critical = Color(.systemRed)
    static let attention = Color(.systemOrange)
    static let positive = Color(.systemGreen)

    static let compactSpacing: Double = 4
    static let standardSpacing: Double = 8
    static let sectionSpacing: Double = 14
    static let contentPadding: Double = 16
    static let markSize: Double = 22
}
