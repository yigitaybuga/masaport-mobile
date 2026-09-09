import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isLogoutConfirmationPresented = false

    var body: some View {
        NavigationStack {
            List {
                accountCard
                    .mpPlainRow(vertical: 4)

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
                    if let helpURL = URL(string: "https://help.masaport.com") {
                        Link(destination: helpURL) {
                            settingsRow(title: "Yardım merkezi", detail: "help.masaport.com", systemImage: "questionmark.circle.fill", tone: .info, isExternal: true)
                        }
                    }
                    settingsRow(title: "Güvenli mobil oturum", detail: "Erişim bilgileri Keychain'de tutulur; çıkışta bu cihaz için iptal edilir.", systemImage: "lock.shield.fill", tone: .positive)
                } header: {
                    Text("Destek ve güvenlik")
                }

                Section {
                    Button(role: .destructive) {
                        isLogoutConfirmationPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            MPIconTile(systemImage: "rectangle.portrait.and.arrow.right", tone: .critical, size: 30)
                            Text("Bu cihazdan çıkış yap")
                                .font(.body.weight(.medium))
                        }
                    }
                } footer: {
                    VStack(spacing: 4) {
                        MPBrandMark(size: 22)
                            .opacity(0.6)
                        Text(versionText)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
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

    // MARK: Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text(MPAvatar.initials(from: session.user?.name ?? "MP"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(MP.onHero)
                    .frame(width: 60, height: 60)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.user?.name ?? "MasaPort kullanıcısı")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MP.onHero)
                        .lineLimit(1)
                    Text(session.user?.email ?? "—")
                        .font(.subheadline)
                        .foregroundStyle(MP.onHeroSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if let roleName {
                    heroChip(roleName, systemImage: "person.badge.key.fill")
                }
                if let venueName = session.activeVenue?.name {
                    heroChip(venueName, systemImage: "building.2.fill")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MP.heroGradient, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            MPBrandMark(size: 120)
                .opacity(0.08)
                .rotationEffect(.degrees(12))
                .offset(x: 26, y: -22)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        .shadow(color: MP.navyDeep.opacity(0.25), radius: 14, y: 6)
    }

    private func heroChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.caption2.weight(.bold))
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MP.onHero)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(MP.heroFill, in: Capsule())
    }

    // MARK: Rows

    private func venueRow(_ venue: Venue) -> some View {
        let isActive = venue.id == session.activeVenue?.id
        let role = session.user?.venueRoles.first(where: { $0.venueId == venue.id })?.role.displayName
        return Button {
            withAnimation(.snappy(duration: 0.25)) { session.selectVenue(venue) }
        } label: {
            HStack(spacing: 12) {
                MPIconTile(systemImage: "building.2.fill", tone: isActive ? .brand : .neutral, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(.body.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(Color(.label))
                    if let role {
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MP.brand)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func settingsRow(title: String, detail: String, systemImage: String, tone: MPTone, isExternal: Bool = false) -> some View {
        HStack(spacing: 12) {
            MPIconTile(systemImage: systemImage, tone: tone, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color(.label))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isExternal {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 2)
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

extension VenueRole {
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
