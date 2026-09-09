import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var revealsPassword = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero(topInset: proxy.safeAreaInsets.top)

                    VStack(spacing: 14) {
                        formCard

                        if let errorMessage {
                            MPNotice(message: errorMessage)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Button {
                            focusedField = nil
                            Task { await signIn() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting { ProgressView().tint(MP.onBrand) }
                                Text(isSubmitting ? "Giriş yapılıyor…" : "Giriş yap")
                            }
                        }
                        .buttonStyle(MPPrimaryButtonStyle())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                        .animation(.easeOut(duration: 0.2), value: canSubmit)

                        footer
                            .padding(.top, 10)
                    }
                    .animation(.snappy(duration: 0.25), value: errorMessage)
                    .padding(.horizontal, MP.gutter)
                    .padding(.top, -28)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MP.background)
        .onSubmit {
            if focusedField == .email { focusedField = .password }
            else if canSubmit { Task { await signIn() } }
        }
    }

    private func hero(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            MPBrandTile(size: 60)
            VStack(alignment: .leading, spacing: 6) {
                Text("MasaPort Operasyon")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(MP.onHero)
                Text("Host masası, bekleme listesi ve etkinlik check-in'i için servis ekibi girişi.")
                    .font(.subheadline)
                    .foregroundStyle(MP.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, MP.gutter)
        .padding(.top, topInset + 44)
        .padding(.bottom, 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous)
                .fill(MP.heroGradient)
                .padding(.top, -600)
        }
        .overlay(alignment: .topTrailing) {
            MPBrandMark(size: 220)
                .opacity(0.07)
                .rotationEffect(.degrees(14))
                .offset(x: 60, y: topInset - 10)
                .allowsHitTesting(false)
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            field(
                systemImage: "envelope.fill",
                isFocused: focusedField == .email
            ) {
                TextField("E-posta", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
            }

            Divider().padding(.leading, 52)

            field(
                systemImage: "lock.fill",
                isFocused: focusedField == .password
            ) {
                Group {
                    if revealsPassword {
                        TextField("Parola", text: $password)
                    } else {
                        SecureField("Parola", text: $password)
                    }
                }
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)

                Button {
                    revealsPassword.toggle()
                } label: {
                    Image(systemName: revealsPassword ? "eye.slash" : "eye")
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealsPassword ? "Parolayı gizle" : "Parolayı göster")
            }
        }
        .mpCard(padding: 0)
    }

    private func field<Content: View>(
        systemImage: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            MPIconTile(systemImage: systemImage, tone: isFocused ? .brand : .neutral, size: 28)
            content()
                .font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Label("Oturum bu cihazın güvenli alanında saklanır.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
            #if DEBUG
            if DemoMode.isEnabled {
                Text("Demo modu: herhangi bir e-posta ve parola ile giriş yapılır.")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            #endif
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isSubmitting
    }

    @MainActor
    private func signIn() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await session.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
