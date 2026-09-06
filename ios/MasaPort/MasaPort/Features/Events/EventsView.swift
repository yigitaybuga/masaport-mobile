import SwiftUI

struct EventsView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: EventsViewModel
    @State private var showCityPicker = false

    let preset: EventsPreset

    init(preset: EventsPreset) {
        self.preset = preset
        _viewModel = State(initialValue: EventsViewModel(preset: preset))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                filterBar
                switch viewModel.phase {
                case .idle, .loading:
                    ForEach(["skeleton-a", "skeleton-b", "skeleton-c", "skeleton-d"], id: \.self) { _ in
                        HStack(spacing: 14) {
                            MPSkeleton(height: 128, width: 104, radius: 18)
                            VStack(alignment: .leading, spacing: 8) {
                                MPSkeleton(height: 12, width: 90)
                                MPSkeleton(height: 16, width: 200)
                                MPSkeleton(height: 12, width: 140)
                            }
                        }
                        .padding(.horizontal, MP.gutter)
                    }
                case .failed(let message):
                    MPNotice(message: message, actionTitle: "Tekrar dene") { viewModel.load() }
                        .padding(.horizontal, MP.gutter)
                case .loaded:
                    if viewModel.events.isEmpty {
                        MPEmptyState(systemImage: "ticket", title: "Etkinlik bulunamadı", message: "Tarih aralığını veya kategoriyi değiştirmeyi dene.")
                    } else {
                        ForEach(viewModel.events) { event in
                            NavigationLink(value: AppRoute.event(id: event.id)) {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, MP.gutter)
                            .task { await viewModel.loadMoreIfNeeded(current: event) }
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
        .navigationBarTitleDisplayMode(preset.title == "Etkinlikler" ? .large : .inline)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Etkinlik veya mekan ara")
        .onSubmit(of: .search) { viewModel.load() }
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.isEmpty { viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(model.activeCity?.name ?? "Şehir")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showCityPicker) { CityPickerView() }
        .task(id: model.activeCity?.id) {
            viewModel.cityId = model.activeCity?.id
            viewModel.load()
            await viewModel.loadCategories()
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Zaman", selection: $viewModel.range) {
                ForEach(EventsDateRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MP.gutter)
            .onChange(of: viewModel.range) { _, _ in viewModel.load() }

            if !viewModel.categories.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        MPChip(title: "Tümü", isSelected: viewModel.categoryId == nil) {
                            viewModel.categoryId = nil
                            viewModel.load()
                        }
                        ForEach(viewModel.categories) { category in
                            MPChip(title: category.name, isSelected: viewModel.categoryId == category.id) {
                                viewModel.categoryId = viewModel.categoryId == category.id ? nil : category.id
                                viewModel.load()
                            }
                        }
                    }
                    .padding(.horizontal, MP.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.top, 4)
    }
}
