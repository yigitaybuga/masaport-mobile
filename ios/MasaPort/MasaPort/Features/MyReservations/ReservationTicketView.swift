import MapKit
import SwiftUI

struct ReservationTicketView: View {
    let reservation: SavedReservation

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var calendarOutcome: CalendarExport.Outcome?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ticketCard
                if let uuid = reservation.remoteUUID {
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
                } else if reservation.kind == .restaurant {
                    MPNotice(message: "QR kodun ve onay detayların e-posta adresine gönderildi. Girişte adını söylemen yeterli.", tone: .brand)
                }
                actions
            }
            .padding(MP.gutter)
            .padding(.bottom, 32)
        }
        .background(MP.groupedBackground)
        .navigationTitle(reservation.kind == .event ? "Etkinlik kaydı" : "Rezervasyon")
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
                model.reservations.remove(reservation)
                dismiss()
            }
        }
    }

    private var ticketCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MPRemoteImage(url: .media(reservation.image), placeholderSymbol: reservation.kind == .event ? "ticket" : "fork.knife", role: .thumbnail)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    MPGlassBadge(text: statusText, tint: statusTint).padding(12)
                }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.title).font(.title3.weight(.bold))
                    if let subtitle = reservation.subtitle?.nilIfBlank {
                        Text(subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Divider()
                HStack(alignment: .top) {
                    TicketField(label: "Tarih", value: DateFormat.longDay.string(from: reservation.startDate))
                    Spacer()
                    TicketField(label: "Saat", value: reservation.timeText)
                    Spacer()
                    TicketField(label: "Kişi", value: "\(reservation.guestCount)")
                }
                TicketField(label: "Ad", value: reservation.customerName)
                if let note = reservation.note?.nilIfBlank {
                    TicketField(label: "Not", value: note)
                }
                if let remoteId = reservation.remoteId {
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
                    Task { calendarOutcome = await CalendarExport.add(reservation) }
                } label: {
                    Label(calendarOutcome == .added ? "Takvimde" : "Takvime ekle", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(calendarOutcome == .added)
                if let lat = reservation.latitude, let lng = reservation.longitude, lat != 0 {
                    Button {
                        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lng), address: nil)
                        item.name = reservation.title
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                    } label: {
                        Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            HStack(spacing: 10) {
                if let phone = reservation.phone?.nilIfBlank, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) {
                        Label("Mekanı ara", systemImage: "phone.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                if let slug = reservation.listingSlug {
                    NavigationLink(value: AppRoute.listing(slug: slug)) {
                        Label("Mekana git", systemImage: "fork.knife").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else if let eventId = reservation.eventId {
                    NavigationLink(value: AppRoute.event(id: eventId)) {
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
        if !reservation.isUpcoming { return "Geçmiş" }
        return reservation.isPending ? "Onay bekliyor" : "Onaylandı"
    }

    private var statusTint: Color? {
        if !reservation.isUpcoming { return nil }
        return reservation.isPending ? MP.attention : MP.positive
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
