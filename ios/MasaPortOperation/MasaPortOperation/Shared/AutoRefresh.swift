import SwiftUI

/// Otomatik yenilemenin neden tetiklendiği.
enum AutoRefreshTrigger: Equatable {
    /// Ekran göründü veya kimliği (mekan, tarih) değişti; ilk yükleme gibi davranır.
    case appear
    /// Uygulama arka plandan ya da uzun bir kesintiden ön plana döndü.
    case foreground
    /// Ekran açıkken düzenli tazeleme.
    case periodic

    /// Kullanıcı ekranda veri görürken yapılan yenileme; yükleniyor durumu ve hata bildirimi baştan sıfırlanmaz.
    var isSilent: Bool { self != .appear }
}

extension View {
    /// Ekran görünürken veriyi yükler; uygulama ön plana dönünce ve (verilirse) `interval` aralığıyla
    /// sessizce tazeler. Ekran kaybolunca veya uygulama arka plana geçince zamanlayıcı durur.
    /// `id`, eylemin kullandığı tüm değerleri (mekan, tarih) içermelidir; değişince ilk yükleme tekrarlanır.
    func operationAutoRefresh<ID: Equatable>(
        id: ID,
        every interval: Duration? = nil,
        perform action: @escaping @MainActor (AutoRefreshTrigger) async -> Void
    ) -> some View {
        modifier(AutoRefreshModifier(id: id, interval: interval, action: action))
    }
}

private struct AutoRefreshModifier<ID: Equatable>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    /// Son çalışmadan beri arka plana gidildiyse ön plana dönüş her zaman yeniler.
    @State private var didEnterBackground = false
    /// Yalnızca kısa bir kesinti (Denetim Merkezi, sistem uyarısı) olduysa yakın zamanda yenilenmiş veri yeterlidir.
    @State private var wasInterrupted = false
    @State private var lastRefreshAt: Date?

    let id: ID
    let interval: Duration?
    let action: @MainActor (AutoRefreshTrigger) async -> Void

    private struct TaskKey: Equatable {
        let id: ID
        let isActive: Bool
    }

    private static var interruptionGrace: TimeInterval { 30 }

    func body(content: Content) -> some View {
        content
            .task(id: TaskKey(id: id, isActive: scenePhase == .active)) {
                // Arka planda/etkin değilken görev iptal edilir; döngü üst üste binmez.
                guard scenePhase == .active else { return }
                await run()
            }
            .onDisappear {
                // Sekme değişimi gibi görünüm geçişlerinde bir sonraki görünüş her zaman tam yükleme yapar.
                didEnterBackground = false
                wasInterrupted = false
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    didEnterBackground = true
                    wasInterrupted = true
                case .inactive:
                    wasInterrupted = true
                default:
                    break
                }
            }
    }

    private func run() async {
        let trigger: AutoRefreshTrigger?
        if lastRefreshAt == nil {
            // Bu ekranın ilk yüklemesi (açılışta sahne önce etkin olmayabilir); yükleniyor durumu gösterilir.
            trigger = .appear
        } else if didEnterBackground {
            trigger = .foreground
        } else if wasInterrupted {
            let isFresh = lastRefreshAt.map { Date().timeIntervalSince($0) < Self.interruptionGrace } ?? false
            trigger = isFresh ? nil : .foreground
        } else {
            trigger = .appear
        }
        didEnterBackground = false
        wasInterrupted = false

        if let trigger {
            await perform(trigger)
        }

        guard let interval else { return }
        var delay = interval
        if trigger == nil, let lastRefreshAt {
            delay = max(.zero, interval - .seconds(Date().timeIntervalSince(lastRefreshAt)))
        }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await perform(.periodic)
            delay = interval
        }
    }

    private func perform(_ trigger: AutoRefreshTrigger) async {
        await action(trigger)
        // İptal edilen (yarıda kalan) yükleme veriyi tazelemiş sayılmaz.
        guard !Task.isCancelled else { return }
        lastRefreshAt = Date()
    }
}

/// Bir görünüm modelindeki yüklemeleri sıralar: sessiz tazeleme süren bir yüklemenin üstüne binmez,
/// geç dönen eski bir yanıt da daha yeni yüklemenin sonucunun üzerine yazılmaz.
struct LoadGate {
    private var generation = 0
    private(set) var isFetching = false

    /// Yeni bir yükleme başlatır; sessiz istek süren bir yükleme varsa `nil` döner ve atlanır.
    mutating func begin(silent: Bool) -> Int? {
        if silent && isFetching { return nil }
        generation += 1
        isFetching = true
        return generation
    }

    func isCurrent(_ token: Int) -> Bool { token == generation }

    mutating func end(_ token: Int) {
        if token == generation { isFetching = false }
    }
}
