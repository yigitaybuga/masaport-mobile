import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isLogoutConfirmationPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accountRow
                }

                Section {
                    ForEach(session.venues) { venue in
                        venueRow(venue)
                    }
                } header: {
                    Text("Çalışma mekanı")
                } footer: {
                    Text("Bugün, Host Masası ve Bekleme listesi seçili mekanı gösterir.")
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Güvenli mobil oturum")
                                .font(.body)
                            Text("Erişim bilgileri Keychain'de tutulur; çıkış yaptığınızda bu cihaz için iptal edilir.")
                                .font(.footnote)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(MP.brand)
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    Button(role: .destructive) {
                        isLogoutConfirmationPresented = true
                    } label: {
                        Label("Bu cihazdan çıkış yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text(versionText)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MP.background)
            .navigationTitle("Profil")
            .confirmationDialog(
                "Oturum kapatılsın mı?",
                isPresented: $isLogoutConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Çıkış yap", role: .destructive) {
                    Task { await session.logout() }
                }
            } message: {
                Text("Bu cihazdaki güvenli oturum sonlandırılacak.")
            }
        }
    }

    private var accountRow: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(MP.onBrand)
                .frame(width: 52, height: 52)
                .background(MP.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.user?.name ?? "MasaPort kullanıcısı")
                    .font(.headline)
                Text(session.user?.email ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                if let roleName {
                    Text(roleName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MP.brand)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func venueRow(_ venue: Venue) -> some View {
        let isActive = venue.id == session.activeVenue?.id
        return Button {
            withAnimation(.snappy(duration: 0.25)) { session.selectVenue(venue) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "building.2")
                    .foregroundStyle(isActive ? MP.brand : Color(.secondaryLabel))
                    .frame(width: 24)
                Text(venue.name)
                    .foregroundStyle(Color(.label))
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MP.brand)
                }
            }
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var initials: String {
        let parts = (session.user?.name ?? "MP").split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var roleName: String? {
        guard let venueID = session.activeVenue?.id else { return nil }
        return session.user?.venueRoles.first(where: { $0.venueId == venueID })?.role.displayName
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "MasaPort Operasyon \(version) (\(build))"
    }
}

private extension VenueRole {
    var displayName: String {
        switch self {
        case .superAdmin: "Süper yönetici"
        case .venueOwner: "İşletme sahibi"
        case .manager: "Yönetici"
        case .staff: "Ekip"
        case .accounting: "Muhasebe"
        case .host: "Host"
        }
    }
}
