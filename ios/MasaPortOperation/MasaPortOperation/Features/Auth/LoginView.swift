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
        ZStack {
            MP.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                        .padding(.top, 72)

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
                    }
                    .animation(.snappy(duration: 0.25), value: errorMessage)

                    footer
                }
                .padding(.horizontal, MP.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onSubmit {
            if focusedField == .email { focusedField = .password }
            else if canSubmit { Task { await signIn() } }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            MPBrandMark(size: 56)
                .padding(18)
                .background(MP.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 4) {
                Text("MasaPort Operasyon")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(.label))
                Text("Servis ekibi için giriş")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            field(
                systemImage: "envelope",
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

            Divider().padding(.leading, 46)

            field(
                systemImage: "lock",
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
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
    }

    private func field<Content: View>(
        systemImage: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(isFocused ? MP.brand : Color(.secondaryLabel))
                .frame(width: 22)
            content()
                .font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
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
