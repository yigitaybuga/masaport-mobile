import SwiftUI

struct OperationWidgetMetric: View {
    let value: Int
    let label: String
    let systemImage: String
    var tint: Color = OperationWidgetDesign.brand
    var isCritical = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCritical ? OperationWidgetDesign.critical : tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value, format: .number)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isCritical ? OperationWidgetDesign.critical : .primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
