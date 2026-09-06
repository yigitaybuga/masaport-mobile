import SwiftUI

struct CityPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var cities: [DiscoveryCity] {
        let all = (model.locations?.cities ?? []).filter { $0.restaurantCount > 0 || $0.upcomingEventCount > 0 }
        guard let term = searchText.nilIfBlank else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.selectCity(nil)
                        Task { await model.resolveCityFromLocation() }
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Konumumu kullan").font(.body.weight(.semibold))
                                Text(model.location.isDenied ? "Konum izni kapalı; Ayarlar'dan açabilirsin." : "Yakınındaki şehir otomatik seçilir")
                                    .font(.caption)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        } icon: {
                            Image(systemName: "location.fill").foregroundStyle(MP.brand)
                        }
                    }
                    .tint(.primary)
                    Button {
                        model.selectCity(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Label("Tüm şehirler", systemImage: "globe.europe.africa")
                            Spacer()
                            if model.preferences.selectedCity == nil {
                                Image(systemName: "checkmark").foregroundStyle(MP.brand)
                            }
                        }
                    }
                    .tint(.primary)
                }

                Section("Şehirler") {
                    if model.locations == nil {
                        MPLoadingRow()
                    } else if cities.isEmpty {
                        Text("Şehir bulunamadı").foregroundStyle(Color(.secondaryLabel))
                    }
                    ForEach(cities) { city in
                        Button {
                            model.selectCity(city.ref)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name)
                                    Text(cityCaption(city))
                                        .font(.caption)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                                Spacer()
                                if model.preferences.selectedCity?.id == city.id {
                                    Image(systemName: "checkmark").foregroundStyle(MP.brand)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Şehir ara")
            .navigationTitle("Şehir seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .task { await model.loadLocations() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func cityCaption(_ city: DiscoveryCity) -> String {
        var parts: [String] = []
        if city.restaurantCount > 0 { parts.append("\(city.restaurantCount) restoran") }
        if city.upcomingEventCount > 0 { parts.append("\(city.upcomingEventCount) etkinlik") }
        return parts.joined(separator: " · ")
    }
}
