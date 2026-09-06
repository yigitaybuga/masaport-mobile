import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showCityPicker = false
    @State private var accountSheet: AccountSheet?

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var preferences = model.preferences
        List {
            AccountSection(activeSheet: $accountSheet)
            Section("Konum") {
                Button {
                    showCityPicker = true
                } label: {
                    HStack {
                        Label("Şehir", systemImage: "mappin.and.ellipse")
                        Spacer()
                        Text(model.activeCity?.name ?? "Otomatik").foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .tint(.primary)
            }

            Section {
                NavigationLink(value: AppRoute.favorites) {
                    HStack {
                        Label("Favoriler", systemImage: "heart")
                        Spacer()
                        Text("\(model.favorites.items.count)").foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }

            Section {
                Toggle(isOn: $preferences.rememberGuest) {
                    Label("Rezervasyon bilgilerimi hatırla", systemImage: "person.text.rectangle")
                }
                if preferences.rememberGuest {
                    TextField("Ad Soyad", text: $preferences.guest.name).textContentType(.name)
                    TextField("Telefon", text: $preferences.guest.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("E-posta", text: $preferences.guest.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
            } header: {
                Text("Misafir bilgileri")
            } footer: {
                Text("Bilgiler yalnızca bu cihazda saklanır ve rezervasyon formunu otomatik doldurmak için kullanılır.")
            }

            Section("MasaPort") {
                Link(destination: AppConfiguration.webBaseURL.appending(path: "business")) {
                    Label("İşletmeni MasaPort'a ekle", systemImage: "storefront")
                }
                Link(destination: URL(string: "https://yardim.masaport.com")!) {
                    Label("Yardım merkezi", systemImage: "questionmark.circle")
                }
                Link(destination: AppConfiguration.webBaseURL.appending(path: "contact")) {
                    Label("Bize yaz", systemImage: "envelope")
                }
                Link(destination: AppConfiguration.webBaseURL.appending(path: "privacy")) {
                    Label("Gizlilik", systemImage: "hand.raised")
                }
            }
            .tint(.primary)

            Section {
                HStack {
                    Text("Sürüm")
                    Spacer()
                    Text(version).foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { dismiss() }
            }
        }
        .sheet(isPresented: $showCityPicker) { CityPickerView() }
        .accountSheets($accountSheet)
    }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.favorites.items.isEmpty {
                MPEmptyState(systemImage: "heart", title: "Favori listen boş", message: "Beğendiğin restoran ve etkinlikleri kalp simgesiyle kaydet.")
            } else {
                List {
                    if !model.favorites.listings.isEmpty {
                        Section("Restoranlar") {
                            ForEach(model.favorites.listings) { item in
                                NavigationLink(value: AppRoute.listing(slug: item.slug ?? "")) {
                                    FavoriteRow(item: item)
                                }
                            }
                            .onDelete { offsets in offsets.map { model.favorites.listings[$0].id }.forEach(model.favorites.remove) }
                        }
                    }
                    if !model.favorites.events.isEmpty {
                        Section("Etkinlikler") {
                            ForEach(model.favorites.events) { item in
                                NavigationLink(value: AppRoute.event(id: item.remoteId)) {
                                    FavoriteRow(item: item)
                                }
                            }
                            .onDelete { offsets in offsets.map { model.favorites.events[$0].id }.forEach(model.favorites.remove) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Favoriler")
    }
}

struct FavoriteRow: View {
    let item: FavoritesStore.Item

    var body: some View {
        HStack(spacing: 12) {
            MPRemoteImage(url: .media(item.image), placeholderSymbol: item.kind == .event ? "ticket" : "fork.knife")
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let subtitle = item.subtitle?.nilIfBlank {
                    Text(subtitle).font(.footnote).foregroundStyle(Color(.secondaryLabel)).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
