import SwiftUI

struct RestaurantsView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: RestaurantsViewModel
    @State private var showFilters = false
    @State private var showCityPicker = false
    @State private var pendingBooking: PendingBooking?

    let preset: ListingsPreset

    init(preset: ListingsPreset) {
        self.preset = preset
        _viewModel = State(initialValue: RestaurantsViewModel(preset: preset))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                filterBar
                switch viewModel.phase {
                case .idle, .loading:
                    ForEach(["skeleton-a", "skeleton-b", "skeleton-c"], id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            MPSkeleton(height: 210, radius: MP.cardRadius)
                            MPSkeleton(height: 16, width: 180)
                            MPSkeleton(height: 12, width: 120)
                        }
                        .padding(.horizontal, MP.gutter)
                    }
                case .failed(let message):
                    MPNotice(message: message, actionTitle: "Tekrar dene") { viewModel.load() }
                        .padding(.horizontal, MP.gutter)
                case .loaded:
                    if viewModel.listings.isEmpty {
                        MPEmptyState(
                            systemImage: "fork.knife",
                            title: viewModel.hasAvailabilityFilter ? "Bu kriterlerde müsait masa yok" : "Restoran bulunamadı",
                            message: viewModel.hasAvailabilityFilter ? "Tarihi, saati veya kişi sayısını değiştirmeyi dene." : "Başka bir şehir veya arama dene.",
                            actionTitle: viewModel.hasAvailabilityFilter ? "Filtreleri temizle" : nil
                        ) { viewModel.clearAvailability() }
                    } else {
                        ForEach(viewModel.listings) { listing in
                            NavigationLink(value: AppRoute.listing(slug: listing.slug)) {
                                RestaurantCard(listing: listing) { time in
                                    pendingBooking = PendingBooking(listing: listing, time: time)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, MP.gutter)
                            .task { await viewModel.loadMoreIfNeeded(current: listing) }
                        }
                        if viewModel.isLoadingMore {
                            MPLoadingRow(title: "Daha fazla yükleniyor")
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(MP.background)
        .navigationTitle(preset.title)
        .navigationBarTitleDisplayMode(preset.title == "Restoranlar" ? .large : .inline)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Restoran veya mutfak ara")
        .onSubmit(of: .search) { viewModel.load() }
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.isEmpty { viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sıralama", selection: $viewModel.orderBy) {
                        Label("Puana göre", systemImage: "star").tag("rating")
                        Label("İsme göre", systemImage: "textformat").tag("name")
                        Label("Yeni eklenenler", systemImage: "sparkles").tag("createdAt")
                        if preset.useLocation {
                            Label("Mesafeye göre", systemImage: "location").tag("distance")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .onChange(of: viewModel.orderBy) { _, _ in viewModel.load() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: viewModel.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filtreler")
            }
        }
        .sheet(isPresented: $showFilters) {
            RestaurantFiltersSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showCityPicker) {
            CityPickerView()
        }
        .sheet(item: $pendingBooking) { booking in
            ReservationFlowView(
                context: ReservationContext(
                    venueId: booking.listing.venue?.id ?? 0,
                    listingId: booking.listing.id,
                    listingSlug: booking.listing.slug,
                    name: booking.listing.name,
                    subtitle: booking.listing.summaryLine,
                    image: booking.listing.image,
                    address: booking.listing.venue?.address ?? booking.listing.location,
                    phone: booking.listing.venue?.phone,
                    latitude: booking.listing.latitude?.value,
                    longitude: booking.listing.longitude?.value
                ),
                initialDate: viewModel.date ?? Calendar.istanbul.startOfDay(for: .now),
                initialGuests: viewModel.guestCount ?? 2,
                initialTime: booking.time
            )
        }
        .task(id: model.activeCity?.id) {
            if preset.query.cityId == nil, preset.listingIds.isEmpty, !preset.useLocation {
                viewModel.cityId = model.activeCity?.id
            }
            if preset.useLocation {
                if model.location.coordinate == nil { await model.resolveCityFromLocation() }
                if let coordinate = model.location.coordinate {
                    viewModel.setCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
            }
            viewModel.load()
            await viewModel.loadFilters()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if !preset.useLocation, preset.listingIds.isEmpty {
                    MPChip(title: model.activeCity?.name ?? "Tüm şehirler", systemImage: "mappin", isSelected: model.activeCity != nil) {
                        showCityPicker = true
                    }
                }
                if let summary = viewModel.availabilitySummary {
                    MPChip(title: summary, systemImage: "calendar", isSelected: true) { showFilters = true }
                    Button {
                        viewModel.clearAvailability()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(MP.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Müsaitlik filtresini kaldır")
                } else {
                    MPChip(title: "Tarih ve kişi", systemImage: "calendar") { showFilters = true }
                }
                if viewModel.phase == .loaded, viewModel.total > 0 {
                    Text("\(viewModel.total) mekan")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, MP.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 4)
    }
}

struct PendingBooking: Identifiable {
    let id = UUID()
    let listing: ListingCard
    let time: String?
}

// MARK: - Filtreler

struct RestaurantFiltersSheet: View {
    @Bindable var viewModel: RestaurantsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var date: Date
    @State private var useDate: Bool
    @State private var time: String?
    @State private var guests: Int
    @State private var districtId: Int?

    init(viewModel: RestaurantsViewModel) {
        self.viewModel = viewModel
        _date = State(initialValue: viewModel.date ?? Calendar.istanbul.startOfDay(for: .now))
        _useDate = State(initialValue: viewModel.date != nil || viewModel.guestCount != nil)
        _time = State(initialValue: viewModel.startTime)
        _guests = State(initialValue: viewModel.guestCount ?? viewModel.filters?.defaultGuestCount ?? 2)
        _districtId = State(initialValue: viewModel.districtId)
    }

    private var timeOptions: [String] {
        viewModel.filters?.timeOptions ?? stride(from: 11, through: 23, by: 1).flatMap { hour in ["\(String(format: "%02d", hour)):00", "\(String(format: "%02d", hour)):30"] }
    }

    private var districts: [DiscoveryDistrict] {
        guard let cityId = viewModel.cityId else { return [] }
        return model.locations?.districts.filter { $0.cityId == cityId && $0.restaurantCount > 0 } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Müsaitliğe göre filtrele", isOn: $useDate.animation())
                    if useDate {
                        DatePicker("Tarih", selection: $date, in: Calendar.istanbul.startOfDay(for: .now)..., displayedComponents: .date)
                            .environment(\.calendar, .istanbul)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                        MPStepper(title: "Kişi sayısı", value: $guests, range: 1...(viewModel.filters?.maxGuestCapacity ?? 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saat").font(.subheadline.weight(.semibold))
                            Text("Seçtiğin saatin 2 saat sonrasına kadar müsait masalar listelenir.")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    MPTimeChip(time: "Fark etmez", isSelected: time == nil) { time = nil }
                                    ForEach(timeOptions, id: \.self) { option in
                                        MPTimeChip(time: option, isSelected: time == option) { time = option }
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Ne zaman?")
                }

                if !districts.isEmpty {
                    Section("Semt") {
                        Picker("Semt", selection: $districtId) {
                            Text("Tümü").tag(Int?.none)
                            ForEach(districts) { district in
                                Text("\(district.name) (\(district.restaurantCount))").tag(Int?.some(district.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
            }
            .navigationTitle("Filtreler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Temizle") {
                        useDate = false
                        time = nil
                        districtId = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        viewModel.date = useDate ? date : nil
                        viewModel.startTime = useDate ? time : nil
                        viewModel.guestCount = useDate ? guests : nil
                        viewModel.districtId = districtId
                        viewModel.load()
                        dismiss()
                    }
                    .buttonStyle(.glassProminent).tint(MP.action)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
