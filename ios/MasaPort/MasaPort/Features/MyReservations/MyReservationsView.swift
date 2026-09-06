import SwiftUI

struct MyReservationsView: View {
    @Environment(AppModel.self) private var model
    @State private var showProfile = false
    @State private var showLogin = false
    @State private var remote: [SavedReservation] = []
    @State private var remoteError: String?
    @State private var isLoadingRemote = false

    /// Sunucudaki (hesaba bağlı) kayıtlar ile cihazdaki kayıtların birleşimi; aynı kayıt bir kez görünür.
    /// Sunucu kaydı önce gelir: yerel kayıt UUID'siz (eski sürüm) olsa bile QR sunucu kaydından gösterilir.
    private var merged: [SavedReservation] {
        var seen = Set<String>()
        var result: [SavedReservation] = []
        for reservation in remote + model.reservations.reservations {
            let keys = [
                reservation.remoteId.map { "\(reservation.kind.rawValue)-\($0)" },
                reservation.remoteUUID.map { "uuid-\($0.lowercased())" },
            ].compactMap { $0 }
            let duplicate = keys.contains(where: seen.contains)
            keys.forEach { seen.insert($0) }
            if keys.isEmpty { seen.insert(reservation.id.uuidString) }
            if !duplicate { result.append(reservation) }
        }
        return result
    }

    private var upcoming: [SavedReservation] { merged.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate } }
    private var past: [SavedReservation] { merged.filter { !$0.isUpcoming }.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        Group {
            if merged.isEmpty {
                ScrollView {
                    MPEmptyState(
                        systemImage: "calendar.badge.plus",
                        title: "Henüz rezervasyonun yok",
                        message: "Uygulamadan yaptığın rezervasyonlar ve etkinlik kayıtları burada görünür."
                    )
                    .padding(.top, 60)
                    NavigationLink(value: AppRoute.listings(ListingsPreset())) {
                        Label("Restoranları keşfet", systemImage: "fork.knife")
                    }
                    .buttonStyle(.glassProminent).tint(MP.action)
                    .controlSize(.large)
                    if !model.customerSession.isLoggedIn {
                        Button("Giriş yap") { showLogin = true }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .padding(.top, 8)
                    }
                }
                .refreshable { await loadRemote() }
            } else {
                List {
                    if !model.customerSession.isLoggedIn {
                        Section { loginBanner }
                    } else if let remoteError {
                        Section { MPNotice(message: remoteError, actionTitle: "Tekrar dene") { Task { await loadRemote() } }.mpPlainRow() }
                    }
                    if !upcoming.isEmpty {
                        Section("Yaklaşan") {
                            ForEach(upcoming) { reservation in
                                NavigationLink(value: AppRoute.reservation(reservation)) {
                                    ReservationRow(reservation: reservation)
                                }
                            }
                        }
                    }
                    if !past.isEmpty {
                        Section("Geçmiş") {
                            ForEach(past) { reservation in
                                NavigationLink(value: AppRoute.reservation(reservation)) {
                                    ReservationRow(reservation: reservation).opacity(0.7)
                                }
                            }
                        }
                    }
                    Section {
                        Text(model.customerSession.isLoggedIn
                             ? "Hesabına bağlı rezervasyonlar ve bu cihazda yaptıkların birlikte listelenir. İptal ve değişiklik için mekanı arayabilirsin."
                             : "Bu liste cihazında saklanır. Giriş yaparsan rezervasyonlarını tüm cihazlarında görebilirsin.")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await loadRemote() }
            }
        }
        .background(MP.groupedBackground)
        .navigationTitle("Rezervasyonlar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profil ve ayarlar")
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { ProfileView().appRoutes() }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
        }
        .task(id: model.customerSession.account?.id) {
            await loadRemote()
        }
    }

    private var loginBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rezervasyonlarını her cihazda gör", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text("Giriş yap; hesabına ve e-postana bağlı rezervasyonlar burada listelensin.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            Button("Giriş yap") { showLogin = true }
                .buttonStyle(.glass)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private func loadRemote() async {
        guard model.customerSession.isLoggedIn else {
            remote = []
            return
        }
        isLoadingRemote = true
        defer { isLoadingRemote = false }
        do {
            remote = try await model.customerSession.reservations().compactMap { $0.asSavedReservation() }
            remoteError = nil
        } catch {
            remoteError = AuthValidation.message(for: error)
        }
    }
}

struct ReservationRow: View {
    let reservation: SavedReservation

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(DateFormat.weekdayShort.string(from: reservation.startDate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Text(Calendar.istanbul.component(.day, from: reservation.startDate), format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 44)
            MPRemoteImage(url: .media(reservation.image), placeholderSymbol: reservation.kind == .event ? "ticket" : "fork.knife", role: .thumbnail)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(reservation.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(reservation.timeText) · \(Format.guests(reservation.guestCount))")
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                if reservation.isPending {
                    MPPill(text: "Onay bekliyor", tone: .attention)
                }
            }
            Spacer(minLength: 0)
            if reservation.isUpcoming, reservation.remoteUUID != nil {
                Image(systemName: "qrcode")
                    .font(.title3)
                    .foregroundStyle(Color(.secondaryLabel))
                    .accessibilityLabel("QR kodu hazır")
            }
        }
        .padding(.vertical, 4)
    }
}
