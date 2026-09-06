import SwiftUI

enum OperationTab: Hashable {
    case today
    case hostDesk
    case events
    case profile
}

/// Sekmeler arasında programatik geçiş için paylaşılan gezinme durumu.
@MainActor
final class OperationNavigation: ObservableObject {
    @Published var tab: OperationTab = .today
}
