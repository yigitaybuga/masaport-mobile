import SwiftUI

/// Hesap bölümünden açılan alt ekranlar. `List` içindeki `Section`'a `.sheet` bağlanamadığı için
/// sunum ProfileView'daki listeye bağlanır; bkz. `accountSheets(_:)`.
enum AccountSheet: String, Identifiable {
    case login, edit, preferences, devices, password, delete
    var id: String { rawValue }
}

extension View {
    /// Hesap alt ekranlarını sunar; `AccountSection`'ı barındıran listeye uygulanır.
    func accountSheets(_ sheet: Binding<AccountSheet?>) -> some View {
        self.sheet(item: sheet) { active in
            NavigationStack {
                switch active {
                case .login: LoginView()
                case .edit: EditAccountView()
                case .preferences: PreferencesEditView()
                case .devices: DeviceSessionsView()
                case .password: ChangePasswordView()
                case .delete: DeleteAccountView()
                }
            }
        }
    }
}

/// Profil ekranının üstünde hesap durumu: giriş yapılmamışsa çağrı, yapılmışsa özet ve işlemler.
struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @Binding var activeSheet: AccountSheet?
    @State private var confirmLogout = false

    var body: some View {
        if let account = model.customerSession.account {
            Section {
                HStack(spacing: 14) {
                    Text(account.initials)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MP.onBrand)
                        .frame(width: 48, height: 48)
                        .background(MP.brand, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.headline)
                        Text(account.email).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                        if let since = memberSince(account) {
                            Text("\(since) tarihinden beri üye")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .textCase(.uppercase)
                        }
                    }
                }
                .padding(.vertical, 4)

                if account.completionRatio < 1 {
                    Button { activeSheet = .edit } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Profilini tamamla", systemImage: "sparkles")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("%\(Int(account.completionRatio * 100))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(MP.brand)
                            }
                            ProgressView(value: account.completionRatio).tint(MP.brand)
                            Text(missingSummary(account))
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        .padding(.vertical, 2)
                    }
                    .tint(.primary)
                }

                Button { activeSheet = .edit } label: { Label("Bilgilerim", systemImage: "person.text.rectangle") }.tint(.primary)
                Button { activeSheet = .preferences } label: {
                    HStack {
                        Label("Tercihlerim", systemImage: "fork.knife.circle")
                        Spacer()
                        Text(preferencesSummary(account)).foregroundStyle(Color(.secondaryLabel)).lineLimit(1)
                    }
                }
                .tint(.primary)
                Button { activeSheet = .devices } label: { Label("Giriş yapılan cihazlar", systemImage: "laptopcomputer.and.iphone") }.tint(.primary)
                Button { activeSheet = .password } label: { Label("Şifre değiştir", systemImage: "key") }.tint(.primary)
                Button(role: .destructive) { confirmLogout = true } label: { Label("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right") }
            } header: {
                Text("Hesabım")
            } footer: {
                Text("Giriş yapmışken yaptığın rezervasyonlar ve bu e-postayla yapılan rezervasyonlar Rezervasyonlar sekmesinde görünür.")
            }
            .confirmationDialog("Çıkış yapmak istiyor musun?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Çıkış yap", role: .destructive) { Task { await model.customerSession.logout() } }
            }

            Section {
                Button(role: .destructive) { activeSheet = .delete } label: {
                    Label("Hesabımı sil", systemImage: "trash")
                }
            } footer: {
                Text("Giriş bilgilerin, profilin ve tercihlerin kalıcı olarak silinir. Mekânlardaki rezervasyon kayıtların işletmede kalır.")
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("MasaPort hesabı", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("Rezervasyonlarını tüm cihazlarında gör, formları saniyeler içinde doldur.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                    Button("Giriş yap veya kayıt ol") { activeSheet = .login }
                        .buttonStyle(.glassProminent).tint(MP.action)
                        .controlSize(.regular)
                        .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func memberSince(_ account: CustomerAccount) -> String? {
        guard let date = account.createdAt.flatMap(ISO8601Parser.date(from:)) else { return nil }
        return DateFormat.monthYear.string(from: date)
    }

    private func missingSummary(_ account: CustomerAccount) -> String {
        var missing: [String] = []
        if account.phone?.nilIfBlank == nil { missing.append("telefon") }
        if account.birthDate?.nilIfBlank == nil { missing.append("doğum tarihi") }
        if account.preferences?.isEmpty != false { missing.append("tercihler") }
        return "Eksik: " + missing.joined(separator: ", ")
    }

    private func preferencesSummary(_ account: CustomerAccount) -> String {
        let keys = (account.preferences?.dietary ?? []) + (account.preferences?.seating ?? [])
        guard !keys.isEmpty else { return "Seçilmedi" }
        let labels = keys.prefix(2).map(CustomerPreferences.label(for:))
        return keys.count > 2 ? labels.joined(separator: ", ") + " +\(keys.count - 2)" : labels.joined(separator: ", ")
    }
}

struct EditAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var marketing = false
    @State private var error: String?
    @State private var isSaving = false

    private var latestAllowedBirthDate: Date {
        Calendar.istanbul.date(byAdding: .year, value: -13, to: .now) ?? .now
    }

    var body: some View {
        Form {
            Section {
                TextField("Ad Soyad", text: $name).textContentType(.name)
                TextField("Telefon", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                LabeledContent("E-posta") {
                    HStack(spacing: 6) {
                        Text(model.customerSession.account?.email ?? "")
                        if model.customerSession.account?.emailVerified == true {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(MP.positive).accessibilityLabel("Doğrulandı")
                        }
                    }
                }
            } footer: {
                Text("Telefon rezervasyon formlarında otomatik doldurulur. E-posta giriş kimliğindir ve şimdilik değiştirilemez.")
            }
            Section {
                Toggle("Doğum tarihimi ekle", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker("Doğum tarihi", selection: $birthDate, in: ...latestAllowedBirthDate, displayedComponents: .date)
                }
            } footer: {
                Text("İsteğe bağlı. Mekânlar özel günlerinde seni hatırlayabilir.")
            }
            Section {
                Toggle("Yeni mekan ve etkinliklerden haberdar ol", isOn: $marketing)
            } footer: {
                Text("Rezervasyon onayı ve hesap güvenliği e-postaları her zaman gönderilir.")
            }
            if let error {
                Section { MPNotice(message: error).mpPlainRow() }
            }
        }
        .navigationTitle("Bilgilerim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Kaydediliyor" : "Kaydet") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).count < 2)
            }
        }
        .onAppear {
            let account = model.customerSession.account
            name = account?.name ?? ""
            phone = account?.phone ?? ""
            marketing = account?.marketingConsent ?? false
            if let stored = account?.birthDateValue {
                hasBirthDate = true
                birthDate = stored
            } else {
                hasBirthDate = false
                birthDate = Calendar.istanbul.date(byAdding: .year, value: -30, to: .now) ?? .now
            }
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.customerSession.updateProfile(.init(
                name: name.trimmingCharacters(in: .whitespaces),
                phone: AuthValidation.normalizedPhone(phone) ?? "",
                marketingConsent: marketing,
                birthDate: hasBirthDate ? DateFormat.apiDay.string(from: birthDate) : ""
            ))
            dismiss()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

/// Yeme ve masa tercihleri; çoklu seçim, sunucu allowlist'i ile aynı anahtarlar.
struct PreferencesEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dietary: Set<String> = []
    @State private var seating: Set<String> = []
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                ForEach(CustomerPreferences.dietaryOptions) { option in
                    optionRow(option, selection: $dietary)
                }
            } header: {
                Text("Yeme tercihleri ve alerjiler")
            }
            Section {
                ForEach(CustomerPreferences.seatingOptions) { option in
                    optionRow(option, selection: $seating)
                }
            } header: {
                Text("Masa tercihi")
            } footer: {
                Text("Tercihlerin hesabında saklanır ve web ile uygulamada aynı görünür. Mekâna iletmek istediğin bir tercih varsa şimdilik mekânı aramanı öneririz.")
            }
            if let error {
                Section { MPNotice(message: error).mpPlainRow() }
            }
        }
        .navigationTitle("Tercihlerim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Kaydediliyor" : "Kaydet") { Task { await save() } }.disabled(isSaving)
            }
        }
        .onAppear {
            dietary = Set(model.customerSession.account?.preferences?.dietary ?? [])
            seating = Set(model.customerSession.account?.preferences?.seating ?? [])
        }
    }

    private func optionRow(_ option: CustomerPreferences.Option, selection: Binding<Set<String>>) -> some View {
        Button {
            if selection.wrappedValue.contains(option.key) {
                selection.wrappedValue.remove(option.key)
            } else {
                selection.wrappedValue.insert(option.key)
            }
        } label: {
            HStack {
                Text(option.label)
                Spacer()
                if selection.wrappedValue.contains(option.key) {
                    Image(systemName: "checkmark").foregroundStyle(MP.brand).fontWeight(.semibold)
                }
            }
        }
        .tint(.primary)
        .accessibilityAddTraits(selection.wrappedValue.contains(option.key) ? .isSelected : [])
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let ordered = CustomerPreferences(
                dietary: CustomerPreferences.dietaryOptions.map(\.key).filter(dietary.contains),
                seating: CustomerPreferences.seatingOptions.map(\.key).filter(seating.contains)
            )
            try await model.customerSession.updateProfile(.init(preferences: ordered))
            dismiss()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

/// Aktif oturumlar (cihazlar); tek tek veya toplu kapatma.
struct DeviceSessionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [CustomerDeviceSession]?
    @State private var error: String?
    @State private var busyId: String?
    @State private var confirmRevokeOthers = false

    private var others: [CustomerDeviceSession] { (sessions ?? []).filter { !$0.isCurrent } }

    var body: some View {
        List {
            if let error {
                Section { MPNotice(message: error, actionTitle: "Tekrar dene") { Task { await load() } }.mpPlainRow() }
            } else if let sessions {
                Section {
                    ForEach(sessions) { session in
                        HStack(spacing: 12) {
                            Image(systemName: session.symbolName)
                                .font(.title3)
                                .foregroundStyle(session.isCurrent ? MP.positive : Color(.secondaryLabel))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(session.device).font(.subheadline.weight(.semibold))
                                    if session.isCurrent { MPPill(text: "Bu cihaz", tone: .positive) }
                                }
                                Text(lastUsed(session)).font(.caption).foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer()
                            if busyId == session.id {
                                ProgressView()
                            } else {
                                Button(session.isCurrent ? "Çıkış" : "Kapat") { Task { await revoke(session) } }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Aktif oturumlar")
                } footer: {
                    Text("Tanımadığın bir cihaz görürsen oturumunu kapat ve şifreni değiştir.")
                }
                if !others.isEmpty {
                    Section {
                        Button(role: .destructive) { confirmRevokeOthers = true } label: {
                            Label("Diğer cihazlardan çık", systemImage: "xmark.circle")
                        }
                        .disabled(busyId != nil)
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .navigationTitle("Cihazlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
        }
        .task { await load() }
        .confirmationDialog("Bu cihaz hariç tüm oturumlar kapatılacak.", isPresented: $confirmRevokeOthers, titleVisibility: .visible) {
            Button("Diğer cihazlardan çık", role: .destructive) { Task { await revokeOthers() } }
        }
    }

    private func lastUsed(_ session: CustomerDeviceSession) -> String {
        guard let date = session.lastUsedDate else { return "Son kullanım bilinmiyor" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .short
        return "Son kullanım: " + (Date.now.timeIntervalSince(date) < 90 ? "az önce" : formatter.localizedString(for: date, relativeTo: .now))
    }

    private func load() async {
        error = nil
        do {
            sessions = try await model.customerSession.deviceSessions()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }

    private func revoke(_ session: CustomerDeviceSession) async {
        busyId = session.id
        defer { busyId = nil }
        do {
            try await model.customerSession.revokeDeviceSession(session)
            if session.isCurrent {
                dismiss()
            } else {
                sessions?.removeAll { $0.id == session.id }
            }
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }

    private func revokeOthers() async {
        busyId = "others"
        defer { busyId = nil }
        do {
            try await model.customerSession.revokeOtherDeviceSessions()
            sessions = sessions?.filter(\.isCurrent)
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

struct ChangePasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                SecureField("Mevcut şifre", text: $current).textContentType(.password)
                SecureField("Yeni şifre", text: $new).textContentType(.newPassword)
                SecureField("Yeni şifre (tekrar)", text: $confirm).textContentType(.newPassword)
            } footer: {
                Text("Yeni şifre en az 8 karakter olmalı ve harf ile rakam içermeli. Diğer cihazlardaki oturumların kapatılır.")
            }
            if !confirm.isEmpty, confirm != new {
                Section { MPNotice(message: "Yeni şifreler birbiriyle eşleşmiyor.").mpPlainRow() }
            }
            if let error {
                Section { MPNotice(message: error).mpPlainRow() }
            }
        }
        .navigationTitle("Şifre değiştir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Güncelleniyor" : "Güncelle") { Task { await save() } }
                    .disabled(isSaving || current.isEmpty || !AuthValidation.isValidPassword(new) || confirm != new)
            }
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.customerSession.changePassword(current: current, new: new)
            dismiss()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

/// Şifre + "SİL" onayıyla kalıcı hesap silme (App Store hesap silme gerekliliği).
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var isDeleting = false

    private var canDelete: Bool {
        !password.isEmpty && confirmation.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr_TR")) == "sil"
    }

    var body: some View {
        Form {
            Section {
                MPNotice(message: "Giriş bilgilerin, profilin ve tercihlerin kalıcı olarak silinir. Mekânlarda yaptığın rezervasyon kayıtları ilgili işletmede kalır. Bu işlem geri alınamaz.").mpPlainRow()
            }
            Section {
                SecureField("Şifren", text: $password).textContentType(.password)
                TextField("Onaylamak için SİL yaz", text: $confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled()
            } footer: {
                Text(model.customerSession.account.map { "\($0.email) hesabı kapatılacak." } ?? "")
            }
            if let error {
                Section { MPNotice(message: error).mpPlainRow() }
            }
            Section {
                Button(role: .destructive) { Task { await deleteAccount() } } label: {
                    HStack {
                        Spacer()
                        if isDeleting { ProgressView().padding(.trailing, 6) }
                        Text(isDeleting ? "Siliniyor" : "Hesabı kalıcı olarak sil").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!canDelete || isDeleting)
            }
        }
        .navigationTitle("Hesabı sil")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isDeleting)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() }.disabled(isDeleting) }
        }
    }

    private func deleteAccount() async {
        error = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await model.customerSession.deleteAccount(password: password)
            dismiss()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}
