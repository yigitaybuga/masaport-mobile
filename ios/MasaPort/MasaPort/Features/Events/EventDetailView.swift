import MapKit
import SwiftUI

@MainActor
@Observable
final class EventDetailViewModel {
    enum Phase: Equatable { case loading, loaded, failed(String) }

    private(set) var phase: Phase = .loading
    private(set) var event: EventDetail?
    private let api: PublicAPI

    init(api: PublicAPI = .shared) { self.api = api }

    func load(id: Int) async {
        do {
            event = try await api.event(id: id)
            phase = .loaded
        } catch {
            phase = .failed((error as? APIError)?.message ?? error.localizedDescription)
        }
    }
}

struct EventDetailView: View {
    let eventID: Int

    @Environment(AppModel.self) private var model
    @State private var viewModel = EventDetailViewModel()
    @State private var registration: EventRegistrationTarget?
    @State private var safari: SafariDestination?
    @State private var externalTicket: SafariDestination?
    @State private var showAllSessions = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                MPEmptyState(systemImage: "exclamationmark.triangle", title: "Etkinlik yüklenemedi", message: message, actionTitle: "Tekrar dene") {
                    Task { await viewModel.load(id: eventID) }
                }
            case .loaded:
                if let event = viewModel.event { content(event) }
            }
        }
        .background(MP.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let event = viewModel.event {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: AppConfiguration.eventShareURL(eventID: event.id), subject: Text(event.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    FavoriteToolbarButton(item: event.favoriteItem)
                }
            }
        }
        .sheet(item: $registration) { target in
            EventReservationView(event: target.event, instance: target.instance)
        }
        .fullScreenCover(item: $safari) { destination in
            SafariView(url: destination.url).ignoresSafeArea()
        }
        .sheet(item: $externalTicket) { destination in
            ExternalTicketLeaveView(url: destination.url)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task { await viewModel.load(id: eventID) }
    }

    private func content(_ event: EventDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MPRemoteImage(url: .media(event.imageUrl), placeholderSymbol: "ticket")
                    .frame(height: 380)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, MP.background], startPoint: .init(x: 0.5, y: 0.6), endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 8) {
                            if let category = event.category {
                                MPGlassBadge(text: category.name, systemImage: "tag.fill")
                            }
                            if let first = event.upcomingInstances.first?.startDate {
                                MPGlassBadge(text: Format.eventDate(first), systemImage: "calendar")
                            }
                        }
                        .padding(.horizontal, MP.gutter)
                        .padding(.bottom, 4)
                    }
                    .backgroundExtensionEffect()

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Label(event.placeLine, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
                            Spacer()
                            priceLabel(event)
                        }
                    }

                    sessions(event)

                    if let description = event.description?.nilIfBlank {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Etkinlik hakkında").font(.title3.weight(.bold))
                            ExpandableText(text: description)
                        }
                    }

                    locationSection(event)
                }
                .padding(.horizontal, MP.gutter)
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .mpHeroTopBar(title: event.title, threshold: 290)
        .safeAreaBar(edge: .bottom) { bottomBar(event) }
    }

    @ViewBuilder
    private func priceLabel(_ event: EventDetail) -> some View {
        if let price = Format.price(event.price) {
            Text("\(price) / kişi").font(.subheadline.weight(.bold)).monospacedDigit()
        } else if event.ticketUrl == nil {
            Text("Ücretsiz").font(.subheadline.weight(.bold)).foregroundStyle(MP.positive)
        }
    }

    @ViewBuilder
    private func sessions(_ event: EventDetail) -> some View {
        let upcoming = event.upcomingInstances
        let shown = showAllSessions ? upcoming : Array(upcoming.prefix(4))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seanslar").font(.title3.weight(.bold))
                Spacer()
                if upcoming.count > 1 {
                    Text("\(upcoming.count) seans").font(.footnote).foregroundStyle(Color(.secondaryLabel))
                }
            }
            if upcoming.isEmpty {
                MPNotice(message: "Yaklaşan seans bulunmuyor.", tone: .neutral)
            }
            ForEach(shown) { instance in
                SessionRow(instance: instance, isExternal: event.ticketUrl != nil) {
                    handleCTA(event, instance: instance)
                }
            }
            if upcoming.count > shown.count {
                Button("Tüm seansları göster") { withAnimation { showAllSessions = true } }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func locationSection(_ event: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konum").font(.title3.weight(.bold))
            if let lat = event.location?.latitude?.value, let lng = event.location?.longitude?.value, lat != 0 {
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)), interactionModes: []) {
                    Marker(event.location?.name ?? event.venue?.name ?? event.title, systemImage: "ticket", coordinate: coordinate)
                        .tint(MP.brand)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                .onTapGesture {
                    let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lng), address: nil)
                    item.name = event.location?.name ?? event.venue?.name
                    item.openInMaps()
                }
            }
            if let name = event.location?.name?.nilIfBlank ?? event.venue?.name {
                Text(name).font(.subheadline.weight(.semibold))
            }
            if let address = event.location?.address?.nilIfBlank ?? event.venue?.address?.nilIfBlank {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private func bottomBar(_ event: EventDetail) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let price = Format.price(event.price) {
                    Text(price).font(.headline).monospacedDigit()
                    Text("kişi başı").font(.caption).foregroundStyle(Color(.secondaryLabel))
                } else if event.ticketUrl == nil {
                    Text("Ücretsiz").font(.headline).foregroundStyle(MP.positive)
                    Text("Kayıt gerekli").font(.caption).foregroundStyle(Color(.secondaryLabel))
                } else {
                    Text("Biletler").font(.headline)
                    Text("Bilet sitesinde").font(.caption).foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
            Button {
                handleCTA(event, instance: event.upcomingInstances.first { !$0.isSoldOut })
            } label: {
                Label(ctaTitle(event), systemImage: event.ticketUrl != nil ? "arrow.up.right.square" : "ticket")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(event.ticketUrl == nil && event.upcomingInstances.allSatisfy(\.isSoldOut))
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func ctaTitle(_ event: EventDetail) -> String {
        if event.ticketUrl != nil { return "Bilet al" }
        if event.upcomingInstances.isEmpty { return "Seans yok" }
        if event.upcomingInstances.allSatisfy(\.isSoldOut) { return "Tükendi" }
        return event.isFree ? "Yer ayırt" : "Bilet al"
    }

    private func handleCTA(_ event: EventDetail, instance: EventInstance?) {
        if let ticket = event.ticketUrl.flatMap(URL.init(string:)) {
            // Harici satış: önce "MasaPort'tan ayrılıyorsun" uyarısı, onaylarsa kullanıcının tarayıcısında açılır.
            externalTicket = SafariDestination(url: ticket)
            return
        }
        guard let instance else { return }
        if event.isFree || model.canPayInApp {
            registration = EventRegistrationTarget(event: event, instance: instance)
        } else {
            // Kart bilgisi isteyen ödeme akışı web'de tamamlanır.
            safari = SafariDestination(url: AppConfiguration.webEventTicketURL(eventID: event.id))
        }
    }
}

struct EventRegistrationTarget: Identifiable {
    let id = UUID()
    let event: EventDetail
    let instance: EventInstance
}

struct SessionRow: View {
    let instance: EventInstance
    var isExternal = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(instance.startDate.map { DateFormat.weekdayShort.string(from: $0) } ?? "–")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Text(instance.startDate.map { String(Calendar.istanbul.component(.day, from: $0)) } ?? "–")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(instance.startDate.map { DateFormat.dayMonth.string(from: $0).components(separatedBy: " ").last ?? "" } ?? "")
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(width: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(instance.startDate.map { DateFormat.time.string(from: $0) } ?? "Saat açıklanacak")
                    .font(.headline)
                    .monospacedDigit()
                if let badge = instance.availabilityBadge {
                    MPPill(text: badge.text, tone: badge.tone)
                } else {
                    Text("Kontenjan sınırsız").font(.caption).foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
            Button(action: action) {
                Text(isExternal ? "Bilet" : (instance.isSoldOut ? "Dolu" : "Seç"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .disabled(!isExternal && instance.isSoldOut)
        }
        .padding(14)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}


/// Harici bilet sitesine geçmeden önce gösterilen uyarı; web'deki "MasaPort'tan ayrılıyorsunuz" akışının karşılığı.
/// Onaylanırsa bağlantı uygulama içinde değil, kullanıcının varsayılan tarayıcısında açılır.
struct ExternalTicketLeaveView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var host: String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.up.right.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(MP.attention)
                .padding(.top, 12)
            VStack(spacing: 8) {
                Text("MasaPort'tan ayrılıyorsun")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let host {
                Label(host, systemImage: "safari")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(MP.fill, in: Capsule())
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button {
                    openURL(url)
                    dismiss()
                } label: {
                    Label("Tarayıcıda aç", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(MP.action)
                .controlSize(.large)
                Button("Vazgeç") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, MP.gutter)
        .padding(.bottom, 16)
        .background(MP.groupedBackground)
    }

    private var message: String {
        var text = "Bu etkinliğin bilet satışı organizatörün kendi sitesinde"
        if let host { text += " (\(host))" }
        text += " yapılıyor. Ödeme ve bilet işlemleri MasaPort güvencesi dışındadır; sayfa tarayıcında açılacak."
        return text
    }
}
