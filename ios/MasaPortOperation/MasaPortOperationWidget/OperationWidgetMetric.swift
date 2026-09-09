import SwiftUI

/// Hero yüzey üzerinde küçük metrik.
struct OperationWidgetMetric: View {
    let value: String
    let label: String
    var tint: Color = OperationWidgetDesign.onHero

    init(value: String, label: String, tint: Color = OperationWidgetDesign.onHero) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    init(value: Int, label: String, tint: Color = OperationWidgetDesign.onHero) {
        self.init(value: value.formatted(), label: label, tint: tint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Karşılanan / beklenen misafir halkası.
struct OperationWidgetRing: View {
    let progress: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(OperationWidgetDesign.heroFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(OperationWidgetDesign.heroPositive, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}
