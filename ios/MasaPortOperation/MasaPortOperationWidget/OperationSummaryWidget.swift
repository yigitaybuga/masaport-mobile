import SwiftUI
import WidgetKit

struct OperationSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: OperationWidgetConfiguration.kind,
            provider: OperationWidgetProvider()
        ) { entry in
            OperationSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Bugünün Operasyonu")
        .description("Rezervasyon, masa ve bekleme listesi özetini hızlıca görün.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
