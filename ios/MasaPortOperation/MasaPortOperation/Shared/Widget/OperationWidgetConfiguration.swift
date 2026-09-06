import Foundation

enum OperationWidgetConfiguration {
    static let appGroupIdentifier = "group.com.masaport.operation"
    static let kind = "MasaPortOperationSummaryWidget"
    static let snapshotKey = "operation-widget-snapshot"

    static var todayURL: URL? {
        URL(string: "masaport-operation://today")
    }
}
