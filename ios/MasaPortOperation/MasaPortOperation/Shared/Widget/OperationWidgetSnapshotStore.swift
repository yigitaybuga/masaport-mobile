import Foundation

enum OperationWidgetSnapshotStore {
    @discardableResult
    static func save(_ snapshot: OperationWidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: OperationWidgetConfiguration.appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else {
            return false
        }
        defaults.set(data, forKey: OperationWidgetConfiguration.snapshotKey)
        return true
    }

    static func load() -> OperationWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: OperationWidgetConfiguration.appGroupIdentifier),
              let data = defaults.data(forKey: OperationWidgetConfiguration.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(OperationWidgetSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: OperationWidgetConfiguration.appGroupIdentifier)?
            .removeObject(forKey: OperationWidgetConfiguration.snapshotKey)
    }
}
