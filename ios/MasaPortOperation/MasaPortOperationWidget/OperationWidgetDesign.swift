import SwiftUI

enum OperationWidgetDesign {
    /// Uygulama ile aynı marka rengi: ikondaki lacivert/slate, koyu modda açık çelik.
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.80, blue: 0.89, alpha: 1)
            : UIColor(red: 0.176, green: 0.216, blue: 0.282, alpha: 1)
    })
    static let critical = Color(.systemRed)
    static let attention = Color(.systemOrange)
    static let positive = Color(.systemGreen)

    static let compactSpacing: Double = 4
    static let standardSpacing: Double = 8
    static let sectionSpacing: Double = 14
    static let contentPadding: Double = 16
    static let markSize: Double = 22
}
