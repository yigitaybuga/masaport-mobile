import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .launching:
                LaunchingView()
            case .signedOut:
                LoginView()
            case .signedIn:
                OperationTabView()
            }
        }
        .animation(.snappy(duration: 0.3), value: session.state)
    }
}

private struct LaunchingView: View {
    var body: some View {
        ZStack {
            MP.background.ignoresSafeArea()
            VStack(spacing: 14) {
                MPBrandMark(size: 64)
                Text("MasaPort")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(.label))
                ProgressView()
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MasaPort Operasyon, oturum kontrol ediliyor")
    }
}

private struct OperationTabView: View {
    @StateObject private var navigation = OperationNavigation()

    var body: some View {
        TabView(selection: $navigation.tab) {
            TodayView()
                .tabItem { Label("Bugün", systemImage: "sun.horizon.fill") }
                .tag(OperationTab.today)

            HostDeskView()
                .tabItem { Label("Host Masası", systemImage: "person.2.fill") }
                .tag(OperationTab.hostDesk)

            EventsView()
                .tabItem { Label("Etkinlikler", systemImage: "ticket.fill") }
                .tag(OperationTab.events)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                .tag(OperationTab.profile)
        }
        .tint(MP.brand)
        .environmentObject(navigation)
        .onOpenURL { url in
            guard url.scheme == "masaport-operation" else { return }
            switch url.host {
            case "today": navigation.tab = .today
            case "host-desk": navigation.tab = .hostDesk
            case "waitlist": navigation.tab = .hostDesk
            case "events": navigation.tab = .events
            case "profile": navigation.tab = .profile
            default: break
            }
        }
    }
}
