import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = DiscoverViewModel()
    @State private var showCityPicker = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                QuickBookingPanel(viewModel: viewModel)
                    .padding(.horizontal, MP.gutter)

                switch viewModel.phase {
                case .idle, .loading:
                    loadingSkeleton
                case .failed(let message):
                    MPNotice(message: message, actionTitle: "Tekrar dene") {
                        Task { await viewModel.load(cityId: model.activeCity?.id, force: true) }
                    }
                    .padding(.horizontal, MP.gutter)
                case .loaded:
                    content
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(MP.background)
        .navigationTitle("Keşfet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MPBrandMark(size: 28)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(model.activeCity?.name ?? "Şehir seç")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showCityPicker) {
            CityPickerView()
        }
        .refreshable {
            await viewModel.load(cityId: model.activeCity?.id, force: true)
        }
        .task(id: model.activeCity?.id) {
            await viewModel.load(cityId: model.activeCity?.id)
        }
        .task {
            if model.preferences.selectedCity == nil {
                await model.resolveCityFromLocation()
            }
            if let coordinate = model.location.coordinate {
                await viewModel.loadNearby(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MP.brand)
            Text(model.activeCity.map { "\($0.name)'da bu akşam ne yapsak?" } ?? "Bu akşam ne yapsak?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Masanı ayırt, etkinlik keşfet, akşamını planla.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal, MP.gutter)
    }

    /// "İyi akşamlar, Ada" — giriş yapılmışsa adla, değilse yalnızca selam.
    private var greeting: String {
        let base = Format.daypartGreeting()
        guard let name = model.customerSession.account?.firstName.nilIfBlank else { return base }
        return "\(base), \(name)"
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.nearby.isEmpty {
            section(title: "Yakınında", subtitle: "Konumuna göre, bugün müsait") {
                horizontalRow(viewModel.nearby) { listing in
                    NavigationLink(value: AppRoute.listing(slug: listing.slug)) {
                        RestaurantTile(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            } more: {
                var preset = ListingsPreset(title: "Yakınındakiler")
                preset.useLocation = true
                preset.query.orderBy = "distance"
                return AppRoute.listings(preset)
            }
        }

        if !viewModel.collections.isEmpty {
            section(title: "Seçkiler", subtitle: "Editör koleksiyonları") {
                horizontalRow(viewModel.collections) { card in
                    NavigationLink(value: AppRoute.listings(ListingsPreset(card: card))) {
                        CollectionTile(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !viewModel.popular.isEmpty {
            section(title: viewModel.popularModule?.title ?? "Popüler restoranlar", subtitle: viewModel.popularModule?.subtitle) {
                horizontalRow(viewModel.popular) { card in
                    NavigationLink(value: AppRoute.listing(slug: card.slug ?? "")) {
                        DiscoveryRestaurantTile(card: card, hydrated: viewModel.hydratedListings[card.id])
                    }
                    .buttonStyle(.plain)
                }
            } more: {
                AppRoute.listings(ListingsPreset(title: "Popüler restoranlar"))
            }
        } else if !viewModel.topRated.isEmpty {
            section(title: "Öne çıkan restoranlar", subtitle: "En yüksek puanlılar") {
                horizontalRow(viewModel.topRated) { listing in
                    NavigationLink(value: AppRoute.listing(slug: listing.slug)) {
                        RestaurantTile(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            } more: {
                AppRoute.listings(ListingsPreset(title: "Restoranlar"))
            }
        }

        if !viewModel.showcaseEvents.isEmpty {
            section(title: "Yaklaşan etkinlikler", subtitle: "Önümüzdeki 14 gün") {
                horizontalRow(viewModel.showcaseEvents) { event in
                    NavigationLink(value: AppRoute.event(id: event.id)) {
                        EventTile(event: event)
                    }
                    .buttonStyle(.plain)
                }
            } more: {
                AppRoute.events(EventsPreset())
            }
        }

        if !viewModel.cuisines.isEmpty {
            section(title: "Mutfağa göre", subtitle: "Canın ne çekiyor?") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.cuisines) { card in
                        NavigationLink(value: AppRoute.listings(ListingsPreset(card: card))) {
                            CuisineTile(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MP.gutter)
            }
        }

        if viewModel.collections.isEmpty, viewModel.popular.isEmpty, viewModel.topRated.isEmpty, viewModel.showcaseEvents.isEmpty {
            MPEmptyState(
                systemImage: "sparkles",
                title: "Bu şehirde henüz vitrin yok",
                message: "Başka bir şehir seçebilir veya tüm restoranlara göz atabilirsin.",
                actionTitle: "Şehir seç"
            ) { showCityPicker = true }
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            MPSkeleton(height: 22, width: 180)
                .padding(.horizontal, MP.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(["skeleton-a", "skeleton-b", "skeleton-c"], id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            MPSkeleton(height: 150, width: 220, radius: MP.radius)
                            MPSkeleton(height: 14, width: 140)
                            MPSkeleton(height: 12, width: 100)
                        }
                    }
                }
                .padding(.horizontal, MP.gutter)
            }
            .scrollDisabled(true)
        }
        .accessibilityLabel("Yükleniyor")
    }

    private func section<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content, more: (() -> AppRoute)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.bold))
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Spacer()
                if let more {
                    NavigationLink(value: more()) {
                        Text("Tümü").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, MP.gutter)
            content()
        }
    }

    private func horizontalRow<Item: Identifiable, Content: View>(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(items) { item in
                    content(item)
                }
            }
            .padding(.horizontal, MP.gutter)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - Alt bileşenler

struct QuickBookingPanel: View {
    @Bindable var viewModel: DiscoverViewModel

    private var dayOptions: [Date] {
        let today = Calendar.istanbul.startOfDay(for: .now)
        return (0..<5).compactMap { Calendar.istanbul.date(byAdding: .day, value: $0, to: today) }
    }

    private let inset: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MP.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Masa ayırt")
                        .font(.headline)
                    Text("Tarihi ve kişi sayısını seç, boş masaları anında gör.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tarih")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .textCase(.uppercase)
                // Çipler kartın kenarına kadar kayar ama kartın dışına taşmaz.
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(dayOptions, id: \.self) { day in
                            MPChip(title: Format.relativeDay(day), isSelected: Calendar.istanbul.isDate(day, inSameDayAs: viewModel.quickDate)) {
                                viewModel.quickDate = day
                            }
                        }
                    }
                    .padding(.horizontal, inset)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -inset)
            }

            MPStepper(title: "Kişi sayısı", value: $viewModel.quickGuests)

            NavigationLink(value: AppRoute.listings(viewModel.quickPreset)) {
                Label("Müsait masaları gör", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
        }
        .padding(inset)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.cardRadius, style: .continuous))
    }
}

struct CollectionTile: View {
    let card: DiscoveryCard
    var width: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MPRemoteImage(url: .media(card.displayImage), placeholderSymbol: "square.stack", role: .card)
                .frame(width: width, height: width * 0.6)
            LinearGradient(
                stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.35), location: 0.6), .init(color: .black.opacity(0.88), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    .lineLimit(2)
                if let description = card.description?.nilIfBlank {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                if card.resolvedListingIds.count > 0 {
                    Text("\(card.resolvedListingIds.count) mekan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(width: width, height: width * 0.6)
        .clipShape(RoundedRectangle(cornerRadius: MP.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CuisineTile: View {
    let card: DiscoveryCard

    var body: some View {
        HStack(spacing: 12) {
            MPRemoteImage(url: .media(card.displayImage), placeholderSymbol: "leaf", role: .card)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(card.resolvedListingIds.isEmpty ? "Keşfet" : "\(card.resolvedListingIds.count) mekan")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
