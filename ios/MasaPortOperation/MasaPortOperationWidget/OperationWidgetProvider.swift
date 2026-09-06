import WidgetKit

struct OperationWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> OperationWidgetEntry {
        OperationWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (OperationWidgetEntry) -> Void) {
        completion(OperationWidgetEntry(date: .now, snapshot: currentSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OperationWidgetEntry>) -> Void) {
        let entry = OperationWidgetEntry(date: .now, snapshot: currentSnapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private var currentSnapshot: OperationWidgetSnapshot {
        OperationWidgetSnapshotStore.load() ?? .empty
    }
}
