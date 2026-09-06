import MapKit
import SwiftUI

@MainActor
@Observable
final class RestaurantDetailViewModel {
    enum Phase: Equatable { case loading, loaded, failed(String) }

    private(set) var phase: Phase = .loading
    private(set) var detail: ListingDetail?
    private(set) var availability: VenueAvailability?
    private(set) var availabilityError: String?
    private(set) var isLoadingAvailability = false

    var selectedDate: Date = Calendar.istanbul.startOfDay(for: .now)
    var guestCount = 2

    private let api: PublicAPI
    private var loadedAvailabilityKey: String?

    init(api: PublicAPI = .shared) { self.api = api }

    var venueId: Int? { detail?.venue?.id }

    var slotOptions: [SlotOption] {
        availability?.slotOptions(for: selectedDate) ?? []
    }

    func load(slug: String) async {
        do {
            detail = try await api.listing(slug: slug)
            phase = .loaded
            await loadAvailability()
        } catch {
            phase = .failed((error as? APIError)?.message ?? error.localizedDescription)
        }
    }

    func loadAvailability(force: Bool = false) async {
        guard let venueId, detail?.isReservationActive != false else { return }
        let key = "\(DateFormat.apiDay.string(from: selectedDate))-\(guestCount)"
        if !force, loadedAvailabilityKey == key { return }
        loadedAvailabilityKey = key
        isLoadingAvailability = true
        availabilityError = nil
        defer { isLoadingAvailability = false }
        do {
            let day = DateFormat.apiDay.string(from: selectedDate)
            availability = try await api.venueAvailability(venueId: venueId, startDate: day, endDate: day, guestCount: guestCount)
        } catch {
            availabilityError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct RestaurantDetailView: View {
    let slug: String

    @Environment(AppModel.self) private var model
    @State private var viewModel = RestaurantDetailViewModel()
    @State private var booking: BookingSelection?
    @State private var safari: SafariDestination?

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                MPEmptyState(systemImage: "exclamationmark.triangle", title: "Restoran yüklenemedi", message: message, actionTitle: "Tekrar dene") {
                    Task { await viewModel.load(slug: slug) }
                }
            case .loaded:
                if let detail = viewModel.detail {
                    content(detail)
                }
            }
        }
        .background(MP.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail = viewModel.detail {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: AppConfiguration.listingShareURL(citySlug: detail.city?.slug, slug: detail.slug), subject: Text(detail.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    FavoriteToolbarButton(item: detail.favoriteItem)
                }
            }
        }
        .sheet(item: $booking) { selection in
            ReservationFlowView(
                context: reservationContext(selection.detail),
                initialDate: viewModel.selectedDate,
                initialGuests: viewModel.guestCount,
                initialTime: selection.slot?.slot.startTime,
                preloadedAvailability: viewModel.availability
            )
        }
        .fullScreenCover(item: $safari) { destination in
            SafariView(url: destination.url).ignoresSafeArea()
        }
        .task { await viewModel.load(slug: slug) }
    }

    @ViewBuilder
    private func content(_ detail: ListingDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero(detail)
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock(detail)
                    if detail.isReservationActive == false {
                        MPNotice(message: "Bu mekan şu anda MasaPort üzerinden rezervasyon almıyor.", tone: .attention)
                    } else if detail.venue != nil {
                        availabilityPanel(detail)
                    }
                    if let description = detail.description?.nilIfBlank {
                        section("Hakkında") {
                            ExpandableText(text: description)
                        }
                    }
                    if let features = detail.features, !features.isEmpty {
                        section("Öne çıkanlar") {
                            FlowLayout(spacing: 8) {
                                ForEach(features, id: \.self) { feature in
                                    MPPill(text: feature, tone: .brand)
                                }
                            }
                        }
                    }
                    if let gallery = detail.gallery, !gallery.isEmpty {
                        section("Galeri") {
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(gallery, id: \.self) { item in
                                        MPRemoteImage(url: .media(item))
                                            .frame(width: 180, height: 130)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                        }
                    }
                    if let hours = detail.workingHours, !hours.isEmpty {
                        section("Çalışma saatleri") { WorkingHoursView(hours: hours) }
                    }
                    if let stats = detail.reviewStats, (stats.totalReviews ?? 0) > 0 {
                        section("Değerlendirmeler") { ReviewsView(stats: stats, reviews: detail.reviews ?? []) }
                    }
                    locationSection(detail)
                }
                .padding(.horizontal, MP.gutter)
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .mpHeroTopBar(title: detail.name, threshold: 250)
        .safeAreaBar(edge: .bottom) {
            if detail.isReservationActive != false, detail.venue != nil {
                bottomBar(detail)
            }
        }
    }

    private func hero(_ detail: ListingDetail) -> some View {
        MPRemoteImage(url: .media(detail.heroImage ?? detail.coverImage))
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, MP.background], startPoint: .init(x: 0.5, y: 0.55), endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    if let rating = Format.rating(detail.reviewStats?.averageRating?.value ?? detail.rating?.value) {
                        MPGlassBadge(text: rating, systemImage: "star.fill")
                    }
                    if let booked = detail.bookedTodayCount, booked > 0 {
                        MPGlassBadge(text: "Bugün \(booked) rezervasyon", systemImage: "flame.fill")
                    }
                }
                .padding(.horizontal, MP.gutter)
                .padding(.bottom, 4)
            }
            .backgroundExtensionEffect()
    }

    private func titleBlock(_ detail: ListingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let logo = URL.media(detail.venue?.logo) {
                    MPRemoteImage(url: logo, contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .background(MP.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.name)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail.summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
    }

    private func availabilityPanel(_ detail: ListingDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Masa ayırt", systemImage: "calendar.badge.clock")
                .font(.headline)
            DayStrip(selected: $viewModel.selectedDate, bleed: 18)
            MPStepper(title: "Kişi sayısı", value: $viewModel.guestCount)
            Group {
                if viewModel.isLoadingAvailability, viewModel.availability == nil {
                    MPLoadingRow(title: "Müsaitlik kontrol ediliyor")
                } else if let error = viewModel.availabilityError {
                    MPNotice(message: error, actionTitle: "Tekrar dene") {
                        Task { await viewModel.loadAvailability(force: true) }
                    }
                } else if viewModel.slotOptions.isEmpty {
                    Text(viewModel.availability?.isSubscriptionActive == false ? "Bu mekan şu anda çevrim içi rezervasyon almıyor." : "Seçtiğin gün için tanımlı saat yok. Başka bir gün dene.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.vertical, 8)
                } else {
                    SlotGrid(options: viewModel.slotOptions, selected: nil) { option in
                        booking = BookingSelection(detail: detail, slot: option)
                    }
                    .opacity(viewModel.isLoadingAvailability ? 0.5 : 1)
                }
            }
            .animation(.default, value: viewModel.isLoadingAvailability)
        }
        .padding(18)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.cardRadius, style: .continuous))
        .onChange(of: viewModel.selectedDate) { _, _ in Task { await viewModel.loadAvailability() } }
        .onChange(of: viewModel.guestCount) { _, _ in Task { await viewModel.loadAvailability() } }
    }

    private func locationSection(_ detail: ListingDetail) -> some View {
        section("Konum") {
            VStack(alignment: .leading, spacing: 12) {
                if let lat = detail.latitude?.value ?? detail.venue?.latitude?.value,
                   let lng = detail.longitude?.value ?? detail.venue?.longitude?.value,
                   lat != 0, lng != 0 {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)), interactionModes: []) {
                        Marker(detail.name, systemImage: "fork.knife", coordinate: coordinate)
                            .tint(MP.brand)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                    .onTapGesture { openInMaps(name: detail.name, coordinate: coordinate) }
                    .accessibilityLabel("Haritada göster")
                }
                if let address = detail.contactAddress?.nilIfBlank ?? detail.venue?.address?.nilIfBlank {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                HStack(spacing: 10) {
                    if let phone = detail.contactPhone?.nilIfBlank ?? detail.venue?.phone?.nilIfBlank,
                       let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                        Link(destination: url) {
                            Label("Ara", systemImage: "phone.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    if let lat = detail.latitude?.value, let lng = detail.longitude?.value, lat != 0 {
                        Button {
                            openInMaps(name: detail.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                        } label: {
                            Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private func bottomBar(_ detail: ListingDetail) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.relativeDay(viewModel.selectedDate))
                    .font(.subheadline.weight(.semibold))
                Text(Format.guests(viewModel.guestCount))
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            Button {
                booking = BookingSelection(detail: detail, slot: nil)
            } label: {
                Label("Rezervasyon yap", systemImage: "calendar.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content()
        }
    }

    private func reservationContext(_ detail: ListingDetail) -> ReservationContext {
        ReservationContext(
            venueId: detail.venue?.id ?? 0,
            listingId: detail.id,
            listingSlug: detail.slug,
            name: detail.name,
            subtitle: detail.summaryLine,
            image: detail.coverImage ?? detail.heroImage,
            address: detail.contactAddress ?? detail.venue?.address ?? detail.location,
            phone: detail.contactPhone ?? detail.venue?.phone,
            latitude: detail.latitude?.value,
            longitude: detail.longitude?.value
        )
    }

    private func openInMaps(name: String, coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

struct BookingSelection: Identifiable {
    let id = UUID()
    let detail: ListingDetail
    let slot: SlotOption?
}

struct FavoriteToolbarButton: View {
    let item: FavoritesStore.Item
    @Environment(AppModel.self) private var model

    private var isFavorite: Bool {
        item.kind == .listing ? model.favorites.isFavorite(listing: item.remoteId) : model.favorites.isFavorite(event: item.remoteId)
    }

    var body: some View {
        Button {
            withAnimation(.bouncy) { model.favorites.toggle(item) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? MP.critical : Color.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
    }
}

// MARK: - Yardımcı görünümler

struct DayStrip: View {
    @Binding var selected: Date
    var days = 14
    /// Şerit bu kadar dışa taşar ve kapsayıcının kenarında kırpılır (kart iç boşluğu kadar ver).
    var bleed: CGFloat = 0

    private var options: [Date] {
        let today = Calendar.istanbul.startOfDay(for: .now)
        return (0..<days).compactMap { Calendar.istanbul.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { day in
                    let isSelected = Calendar.istanbul.isDate(day, inSameDayAs: selected)
                    Button {
                        withAnimation(.snappy) { selected = day }
                    } label: {
                        VStack(spacing: 3) {
                            Text(Calendar.istanbul.isDateInToday(day) ? "Bugün" : DateFormat.weekdayShort.string(from: day))
                                .font(.caption.weight(.semibold))
                            Text(Calendar.istanbul.component(.day, from: day), format: .number)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .monospacedDigit()
                            Text(DateFormat.dayMonth.string(from: day).components(separatedBy: " ").last ?? "")
                                .font(.caption2)
                        }
                        .frame(width: 62, height: 70)
                        .foregroundStyle(isSelected ? MP.onBrand : Color.primary)
                        .background(isSelected ? MP.brand : MP.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DateFormat.longDay.string(from: day))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, bleed)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -bleed)
    }
}

struct SlotGrid: View {
    let options: [SlotOption]
    var selected: Int?
    let onSelect: (SlotOption) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                MPTimeChip(
                    time: option.slot.startTime.shortTime,
                    isSelected: selected == option.id,
                    isEnabled: option.isBookable,
                    caption: option.caption
                ) { onSelect(option) }
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
    }
}

extension SlotOption {
    var caption: String? {
        if !isBookable { return status?.isFull == true ? "Dolu" : "Kapalı" }
        if slot.prepaymentRequired == true { return "Ön ödeme" }
        if slot.isRequestOnly { return "Onaylı" }
        return nil
    }

    var accessibilityLabel: String {
        var parts = [slot.startTime.shortTime]
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }
}

struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color(.label))
                .lineLimit(expanded ? nil : 4)
            if text.count > 180 {
                Button(expanded ? "Daha az" : "Devamını oku") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct WorkingHoursView: View {
    let hours: [String: WorkingDay]

    private let order = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    private let names = ["monday": "Pazartesi", "tuesday": "Salı", "wednesday": "Çarşamba", "thursday": "Perşembe", "friday": "Cuma", "saturday": "Cumartesi", "sunday": "Pazar"]

    private var todayKey: String {
        let weekday = Calendar.istanbul.component(.weekday, from: .now)
        return order[(weekday + 5) % 7]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order, id: \.self) { key in
                if let day = hours[key] {
                    HStack {
                        Text(names[key] ?? key)
                            .font(.subheadline.weight(key == todayKey ? .bold : .regular))
                        Spacer()
                        Text(day.closed == true ? "Kapalı" : "\(day.open ?? "--") – \(day.close ?? "--")")
                            .font(.subheadline.weight(key == todayKey ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(day.closed == true ? MP.critical : Color(.label))
                    }
                    .padding(.vertical, 8)
                    if key != order.last { Divider() }
                }
            }
        }
        .mpCard()
    }
}

struct ReviewsView: View {
    let stats: ReviewStats
    let reviews: [ListingReview]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.rating(stats.averageRating?.value) ?? "–")
                    .font(.system(size: 40, design: .rounded).weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= (stats.averageRating?.value ?? 0).rounded() ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(MP.warm)
                        }
                    }
                    Text("\(stats.totalReviews ?? 0) değerlendirme")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            ForEach(reviews.prefix(5)) { review in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(review.userName ?? "Misafir").font(.subheadline.weight(.semibold))
                        Spacer()
                        if let rating = Format.rating(review.rating?.value) {
                            Label(rating, systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(MP.warm)
                        }
                    }
                    if let comment = review.comment?.nilIfBlank {
                        Text(comment).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(.vertical, 4)
                if review.id != reviews.prefix(5).last?.id { Divider() }
            }
        }
        .mpCard()
    }
}

/// Basit sarmalayıcı düzen: çipleri satır satır dizer.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
