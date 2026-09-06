import Combine
import SwiftUI

// MARK: - Giriş

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var showRegister = false
    @State private var showForgot = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var onLoggedIn: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    MPBrandMark(size: 44)
                    Text("Giriş yap")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Rezervasyonlarını tek yerden gör, formları saniyeler içinde doldur.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .padding(.top, 8)

                VStack(spacing: 14) {
                    MPLabeledField(label: "E-posta") {
                        TextField("E-posta adresin", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    MPLabeledField(label: "Şifre") {
                        SecureField("Şifren", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await submit() } }
                    }
                }

                if let error {
                    MPNotice(message: error)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isSubmitting { ProgressView().tint(MP.onBrand) }
                        Text(isSubmitting ? "Giriş yapılıyor" : "Giriş yap").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(MP.action)
                .controlSize(.large)
                .disabled(isSubmitting || email.isEmpty || password.isEmpty)

                Button("Şifreni mi unuttun?") { showForgot = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Divider().padding(.vertical, 4)

                HStack {
                    Text("Hesabın yok mu?").foregroundStyle(Color(.secondaryLabel))
                    Button("Kayıt ol") { showRegister = true }.fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(MP.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MP.background)
        .navigationTitle("Hesabım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $showRegister) {
            RegisterView(onRegistered: { finish() })
        }
        .navigationDestination(isPresented: $showForgot) {
            ForgotPasswordView(initialEmail: email)
        }
    }

    private func submit() async {
        error = nil
        guard AuthValidation.isValidEmail(email) else { error = "Geçerli bir e-posta adresi gir."; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.customerSession.login(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            finish()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }

    private func finish() {
        onLoggedIn?()
        dismiss()
    }
}

// MARK: - Kayıt

struct RegisterView: View {
    @Environment(AppModel.self) private var model

    enum Step { case form, otp }

    @State private var step: Step = .form
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var privacyAccepted = false
    @State private var marketingConsent = false
    @State private var code = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var resendAt: Date?
    @State private var now = Date.now

    var onRegistered: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var resendSeconds: Int {
        guard let resendAt else { return 0 }
        return max(0, Int(resendAt.timeIntervalSince(now).rounded(.up)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch step {
                case .form: form
                case .otp: otp
                }
            }
            .padding(MP.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MP.background)
        .navigationTitle(step == .form ? "Kayıt ol" : "E-postanı doğrula")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now = $0 }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Restoran ve etkinlik rezervasyonlarını tek hesapta topla.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            VStack(spacing: 14) {
                MPLabeledField(label: "Ad Soyad") {
                    TextField("Adın ve soyadın", text: $name).textContentType(.name)
                }
                MPLabeledField(label: "E-posta", hint: "Doğrulama kodu bu adrese gelir.") {
                    TextField("E-posta adresin", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                MPLabeledField(label: "Telefon (isteğe bağlı)", hint: "Rezervasyon formlarında otomatik doldurulur.") {
                    TextField("+90 5xx xxx xx xx", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                MPLabeledField(label: "Şifre", hint: "En az 8 karakter, harf ve rakam.") {
                    SecureField("Şifre belirle", text: $password).textContentType(.newPassword)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $privacyAccepted) {
                    Text("Kişisel verilerimin hesap ve rezervasyon işlemleri için işlenmesini kabul ediyorum.").font(.subheadline)
                }
                Toggle(isOn: $marketingConsent) {
                    Text("Yeni mekan ve etkinliklerden e-posta ile haberdar olmak istiyorum.").font(.subheadline)
                }
            }
            .padding(16)
            .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            .tint(MP.brand)

            if let error { MPNotice(message: error) }

            Button {
                Task { await submitForm() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView().tint(MP.onBrand) }
                    Text(isSubmitting ? "Kod gönderiliyor" : "Devam et").font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(isSubmitting)
        }
    }

    private var otp: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(email.trimmingCharacters(in: .whitespaces)) adresine 6 haneli bir kod gönderdik. Kod 15 dakika geçerli.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            MPLabeledField(label: "Doğrulama kodu") {
                TextField("••••••", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }
            }
            if let error { MPNotice(message: error) }
            Button {
                Task { await submitCode() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView().tint(MP.onBrand) }
                    Text(isSubmitting ? "Doğrulanıyor" : "Hesabımı oluştur").font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(isSubmitting || code.count != 6)
            Button(resendSeconds > 0 ? "Yeni kod (\(resendSeconds) sn)" : "Yeni kod gönder") {
                Task { await resend() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(resendSeconds > 0 || isSubmitting)
            Button("E-postayı düzelt") { withAnimation { step = .form } }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
    }

    private func submitForm() async {
        error = nil
        guard name.trimmingCharacters(in: .whitespaces).count >= 2 else { error = "Adını ve soyadını gir."; return }
        guard AuthValidation.isValidEmail(email) else { error = "Geçerli bir e-posta adresi gir."; return }
        guard AuthValidation.isValidPassword(password) else { error = "Şifre en az 8 karakter olmalı ve harf ile rakam içermeli."; return }
        guard privacyAccepted else { error = "Devam etmek için kişisel verilerin işlenmesini kabul etmelisin."; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let pending = try await model.customerSession.register(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                phone: AuthValidation.normalizedPhone(phone),
                password: password,
                marketingConsent: marketingConsent
            )
            resendAt = pending.resendAvailableAt.flatMap(ISO8601Parser.date(from:)) ?? Date.now.addingTimeInterval(60)
            #if DEBUG
            if let debugCode = pending.debugCode { code = debugCode }
            #endif
            withAnimation { step = .otp }
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }

    private func submitCode() async {
        error = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.customerSession.verify(email: email.trimmingCharacters(in: .whitespaces).lowercased(), code: code)
            onRegistered()
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }

    private func resend() async {
        error = nil
        do {
            let pending = try await model.customerSession.resendVerification(email: email.trimmingCharacters(in: .whitespaces).lowercased())
            resendAt = pending.resendAvailableAt.flatMap(ISO8601Parser.date(from:)) ?? Date.now.addingTimeInterval(60)
            code = ""
            #if DEBUG
            if let debugCode = pending.debugCode { code = debugCode }
            #endif
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

// MARK: - Şifremi unuttum

struct ForgotPasswordView: View {
    @Environment(AppModel.self) private var model

    @State private var email: String
    @State private var message: String?
    @State private var error: String?
    @State private var isSubmitting = false

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("E-postanı gir; sana şifreni yenilemen için bir bağlantı gönderelim. Bağlantı 1 saat geçerli.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                if let message {
                    MPNotice(message: message, tone: .positive)
                    Text("E-postandaki bağlantıya dokunarak yeni şifreni belirle, sonra buradan giriş yap.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                } else {
                    MPLabeledField(label: "E-posta") {
                        TextField("E-posta adresin", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let error { MPNotice(message: error) }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(MP.onBrand) }
                            Text(isSubmitting ? "Gönderiliyor" : "Sıfırlama bağlantısı gönder").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(MP.action)
                    .controlSize(.large)
                    .disabled(isSubmitting)
                }
            }
            .padding(MP.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MP.background)
        .navigationTitle("Şifremi unuttum")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        error = nil
        guard AuthValidation.isValidEmail(email) else { error = "Geçerli bir e-posta adresi gir."; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            message = try await model.customerSession.forgotPassword(email: email.trimmingCharacters(in: .whitespaces).lowercased())
        } catch {
            self.error = AuthValidation.message(for: error)
        }
    }
}

// MARK: - Doğrulama

enum AuthValidation {
    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 6 && !trimmed.contains(" ")
    }

    static func isValidPassword(_ value: String) -> Bool {
        value.count >= 8 && value.contains(where: \.isLetter) && value.contains(where: \.isNumber)
    }

    static func normalizedPhone(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return trimmed.hasPrefix("+") ? "+\(digits)" : digits
    }

    private static let messages: [String: String] = [
        "INVALID_CREDENTIALS": "E-posta veya şifre hatalı.",
        "EMAIL_ALREADY_REGISTERED": "Bu e-posta ile zaten bir hesabın var. Giriş yapabilir veya şifreni sıfırlayabilirsin.",
        "WEAK_PASSWORD": "Şifre en az 8 karakter olmalı ve harf ile rakam içermeli.",
        "OTP_INVALID": "Kod hatalı. Tekrar dene.",
        "OTP_EXPIRED": "Kodun süresi doldu. Yeni kod iste.",
        "OTP_ATTEMPTS_EXCEEDED": "Çok fazla hatalı deneme. Yeni kod iste.",
        "OTP_RATE_LIMIT": "Yeni kod istemeden önce biraz bekle.",
        "VERIFICATION_NOT_FOUND": "Bu e-posta için bekleyen bir kayıt yok. Yeniden kayıt ol.",
        "CURRENT_PASSWORD_INVALID": "Mevcut şifren hatalı.",
        "CUSTOMER_SESSION_EXPIRED": "Oturumun sona erdi. Lütfen tekrar giriş yap.",
        "INVALID_PHONE": "Geçerli bir telefon numarası gir.",
        "INVALID_NAME": "Adını ve soyadını gir.",
        "INVALID_BIRTH_DATE": "Geçerli bir doğum tarihi gir.",
        "SESSION_NOT_FOUND": "Bu oturum zaten kapatılmış.",
    ]

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            if let code = apiError.code, let known = messages[code] { return known }
            if apiError.isRateLimited { return "Çok fazla deneme yapıldı. Biraz sonra tekrar dene." }
            return apiError.detail ?? apiError.message
        }
        return error.localizedDescription
    }
}
