import MapKit
import SwiftUI

struct ReservationTicketView: View {
    let reservation: SavedReservation

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var calendarOutcome: CalendarExport.Outcome?
    @State private var confirmDelete = false
    @State private var management: SafariDestination?
    @State private var latest: SavedReservation?

    /// Yönetim sayfasından dönünce yenilenen kayıt; yoksa cihazdaki güncel kopya, o da yoksa rotayla gelen değer.
    private var item: SavedReservation {
        latest ?? model.reservations.reservations.first { $0.id == reservation.id } ?? reservation
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ticketCard
                if let uuid = item.remoteUUID, !item.isCancelled {
                    VStack(spacing: 10) {
                        AsyncImage(url: AppConfiguration.qrImageURL(uuid: uuid)) { phase in
                            if let image = phase.image {
                                image.resizable().interpolation(.none).scaledToFit()
                            } else {
                                MPSkeleton(height: 200, width: 200, radius: 16)
                            }
                        }
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text(SavedReservation.shortCode(from: uuid))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .tracking(4)
                            .monospacedDigit()
                        Text("Girişte bu kodu göster; okunamazsa kısa kodu söylemen yeterli.")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                } else if item.kind == .restaurant, !item.isCancelled {
                    MPNotice(message: "QR kodun ve onay detayların e-posta adresine gönderildi. Girişte adını söylemen yeterli.", tone: .brand)
                }
                manageSection
                actions
            }
            .padding(MP.gutter)
            .padding(.bottom, 32)
        }
        .background(MP.groupedBackground)
        .navigationTitle(item.kind == .event ? "Etkinlik kaydı" : "Rezervasyon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Listeden kaldır", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog("Bu kayıt yalnızca cihazından silinir; rezervasyonun iptal olmaz.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Listeden kaldır", role: .destructive) {
                model.reservations.remove(item)
                dismiss()
            }
        }
        .fullScreenCover(item: $management) { destination in
            SafariView(url: destination.url) {
                management = nil
            }
            .ignoresSafeArea()
        }
        .onChange(of: management) { previous, current in
            // Sayfa kapandı: iptal veya değişiklik talebi sonrası durum yenilenir.
            if previous != nil, current == nil {
                Task { await refreshAfterManagement() }
            }
        }
    }

    // MARK: Yönetim

    /// İptal ve değişiklik talepleri app.masaport'taki imzalı misafir sayfasında yapılır.
    @ViewBuilder
    private var manageSection: some View {
        if let link = item.managementLink {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    management = SafariDestination(url: link)
                } label: {
                    Label("Rezervasyonu yönet", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Text("İptal veya tarih, saat ve kişi değişikliği talebini güvenli sayfada iletebilirsin; talebin mekan onayladığında kesinleşir.")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshAfterManagement() async {
        model.reservationsDidChange()
        let current = item
        if model.customerSession.isLoggedIn,
           let list = try? await model.customerSession.reservations(),
           let match = list.compactMap({ $0.asSavedReservation() }).first(where: { $0.refersToSameBooking(as: current) }) {
            model.reservations.refresh(with: match)
            latest = match
            return
        }
        // Hesapsız kayıt: bağlantıdaki misafir token'ıyla güncel durum okunur.
        guard let uuid = current.remoteUUID, let token = current.managementToken,
              let managed = try? await model.api.guestManagedReservation(uuid: uuid, token: token) else { return }
        let updated = current.applying(managed)
        model.reservations.refresh(with: updated)
        latest = updated
    }

    private var ticketCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MPRemoteImage(url: .media(item.image), placeholderSymbol: item.kind == .event ? "ticket" : "fork.knife", role: .thumbnail)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    MPGlassBadge(text: statusText, tint: statusTint).padding(12)
                }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title3.weight(.bold))
                    if let subtitle = item.subtitle?.nilIfBlank {
                        Text(subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Divider()
                HStack(alignment: .top) {
                    TicketField(label: "Tarih", value: DateFormat.longDay.string(from: item.startDate))
                    Spacer()
                    TicketField(label: "Saat", value: item.timeText)
                    Spacer()
                    TicketField(label: "Kişi", value: "\(item.guestCount)")
                }
                TicketField(label: "Ad", value: item.customerName)
                if let note = item.note?.nilIfBlank {
                    TicketField(label: "Not", value: note)
                }
                if let remoteId = item.remoteId {
                    TicketField(label: "Kayıt no", value: "#\(remoteId)")
                }
            }
            .padding(18)
        }
        .background(MP.card)
        .clipShape(RoundedRectangle(cornerRadius: MP.cardRadius, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { calendarOutcome = await CalendarExport.add(item) }
                } label: {
                    Label(calendarOutcome == .added ? "Takvimde" : "Takvime ekle", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(calendarOutcome == .added)
                if let lat = item.latitude, let lng = item.longitude, lat != 0 {
                    Button {
                        let mapItem = MKMapItem(location: CLLocation(latitude: lat, longitude: lng), address: nil)
                        mapItem.name = item.title
                        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                    } label: {
                        Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            HStack(spacing: 10) {
                if let phone = item.phone?.nilIfBlank, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) {
                        Label("Mekanı ara", systemImage: "phone.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                if let slug = item.listingSlug {
                    NavigationLink(value: AppRoute.listing(slug: slug)) {
                        Label("Mekana git", systemImage: "fork.knife").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else if let eventId = item.eventId {
                    NavigationLink(value: AppRoute.eventByID(id: eventId)) {
                        Label("Etkinliğe git", systemImage: "ticket").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            if calendarOutcome == .denied {
                Text("Takvim izni verilmedi. Ayarlar > MasaPort'tan açabilirsin.")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private var statusText: String {
        if item.isCancelled { return "İptal edildi" }
        if !item.isUpcoming { return "Geçmiş" }
        return item.isPending ? "Onay bekliyor" : "Onaylandı"
    }

    private var statusTint: Color? {
        if item.isCancelled { return MP.critical }
        if !item.isUpcoming { return nil }
        return item.isPending ? MP.attention : MP.positive
    }
}

struct TicketField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
