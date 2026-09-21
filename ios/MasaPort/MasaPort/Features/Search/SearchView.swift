import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case restaurants, events
        var id: String { rawValue }
        var title: String { self == .restaurants ? "Restoranlar" : "Etkinlikler" }
    }

    var text = ""
    var scope: Scope = .restaurants
    private(set) var listings: [ListingCard] = []
    private(set) var events: [PublicEvent] = []
    private(set) var isSearching = false
    private(set) var error: String?
    private(set) var lastQuery = ""

    private let api: PublicAPI
    private var task: Task<Void, Never>?

    init(api: PublicAPI = .shared) { self.api = api }

    func search(cityId: Int?) {
        task?.cancel()
        let term = text.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            listings = []
            events = []
            lastQuery = ""
            return
        }
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            error = nil
            defer { isSearching = false }
            do {
                var listingQuery = ListingsQuery()
                listingQuery.query = term
                listingQuery.cityId = cityId
                listingQuery.limit = 30
                var eventQuery = EventsQuery()
                eventQuery.search = term
                eventQuery.cityId = cityId
                eventQuery.startDate = DateFormat.apiDay.string(from: .now)
                async let listingsResult = api.listings(listingQuery)
                async let eventsResult = api.events(eventQuery)
                let (l, e) = try await (listingsResult, eventsResult)
                guard !Task.isCancelled else { return }
                listings = l.listings
                events = e.events
                lastQuery = term
            } catch is CancellationError {
            } catch {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = SearchViewModel()

    private let popularCuisines: [(name: String, symbol: String)] = [
        ("Kahvaltı", "cup.and.saucer.fill"), ("Balık", "fish.fill"), ("Kebap", "flame.fill"), ("İtalyan", "leaf.fill"),
        ("Meze", "fork.knife"), ("Burger", "takeoutbag.and.cup.and.straw.fill"), ("Sushi", "circle.hexagongrid.fill"), ("Vegan", "carrot.fill"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.text.trimmingCharacters(in: .whitespaces).count < 2 {
                    suggestions
                } else {
                    results
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(MP.background)
        .navigationTitle("Ara")
        .searchable(text: $viewModel.text, prompt: "Restoran, mutfak veya etkinlik")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: viewModel.text) { _, _ in viewModel.search(cityId: model.activeCity?.id) }
        .onSubmit(of: .search) {
            model.preferences.rememberSearch(viewModel.text)
            viewModel.search(cityId: model.activeCity?.id)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Bir mutfak seç, şehir değiştir ya da aşağıdan yazmaya başla.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, MP.gutter)

            if !model.preferences.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MPSectionHeader(title: "Son aramalar", actionTitle: "Temizle") { model.preferences.clearRecentSearches() }
                    VStack(spacing: 0) {
                        ForEach(model.preferences.recentSearches, id: \.self) { term in
                            Button {
                                viewModel.text = term
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(Color(.secondaryLabel))
                                        .frame(width: 22)
                                    Text(term)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .tint(.primary)
                            if term != model.preferences.recentSearches.last { Divider().padding(.leading, 48) }
                        }
                    }
                    .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                    .padding(.horizontal, MP.gutter)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                MPSectionHeader(title: "Mutfaklar")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(popularCuisines, id: \.name) { cuisine in
                        Button {
                            viewModel.text = cuisine.name
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: cuisine.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MP.brand)
                                    .frame(width: 34, height: 34)
                                    .background(MP.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(cuisine.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(.label))
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(MP.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MP.gutter)
            }

            if let cities = model.locations?.cities.filter({ $0.restaurantCount > 0 }).prefix(8), !cities.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    MPSectionHeader(title: "Şehirler", subtitle: "Aramalar seçili şehirde yapılır")
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            MPChip(title: "Tümü", systemImage: "globe.europe.africa", isSelected: model.activeCity == nil) {
                                model.selectCity(nil)
                            }
                            ForEach(Array(cities)) { city in
                                MPChip(title: city.name, systemImage: "mappin", isSelected: model.activeCity?.id == city.id) {
                                    model.selectCity(city.ref)
                                }
                            }
                        }
                        .padding(.horizontal, MP.gutter)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            NavigationLink(value: AppRoute.events(EventsPreset(title: "Bu hafta", range: .week))) {
                HStack(spacing: 14) {
                    Image(systemName: "ticket.fill")
                        .font(.title3)
                        .foregroundStyle(MP.onBrand)
                        .frame(width: 44, height: 44)
                        .background(MP.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu haftaki etkinlikler").font(.subheadline.weight(.semibold)).foregroundStyle(Color(.label))
                        Text("Konser, gastronomi, sahne ve daha fazlası").font(.footnote).foregroundStyle(Color(.secondaryLabel))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(12)
                .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MP.gutter)
        }
    }

    @ViewBuilder
    private var results: some View {
        Picker("Kapsam", selection: $viewModel.scope) {
            ForEach(SearchViewModel.Scope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, MP.gutter)

        if viewModel.isSearching, viewModel.lastQuery.isEmpty {
            MPLoadingRow(title: "Aranıyor")
        } else if let error = viewModel.error {
            MPNotice(message: error).padding(.horizontal, MP.gutter)
        } else {
            switch viewModel.scope {
            case .restaurants:
                if viewModel.listings.isEmpty {
                    MPEmptyState(systemImage: "magnifyingglass", title: "Restoran bulunamadı", message: "Farklı bir kelime veya şehir dene.")
                }
                ForEach(viewModel.listings) { listing in
                    NavigationLink(value: AppRoute.listing(slug: listing.slug)) {
                        SearchListingRow(listing: listing)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MP.gutter)
                }
            case .events:
                if viewModel.events.isEmpty {
                    MPEmptyState(systemImage: "ticket", title: "Etkinlik bulunamadı", message: "Farklı bir kelime veya şehir dene.")
                }
                ForEach(viewModel.events) { event in
                    NavigationLink(value: AppRoute.eventByID(id: event.id)) {
                        EventCard(event: event)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MP.gutter)
                }
            }
        }
    }
}

struct SearchListingRow: View {
    let listing: ListingCard

    var body: some View {
        HStack(spacing: 12) {
            MPRemoteImage(url: .media(listing.image), role: .card)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name).font(.headline).lineLimit(1)
                Text(listing.summaryLine).font(.subheadline).foregroundStyle(Color(.secondaryLabel)).lineLimit(1)
                MPRatingLabel(rating: listing.rating?.value)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
