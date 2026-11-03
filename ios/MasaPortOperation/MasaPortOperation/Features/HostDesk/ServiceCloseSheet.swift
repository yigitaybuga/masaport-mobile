import SwiftUI

/// "Kalktı" ile gönderilen isteğe bağlı hesap tutarı. API `^\d{1,8}(\.\d{1,2})?$` biçimini (TRY) bekler.
enum BillAmountInput: Equatable {
    case empty
    case valid(String)
    case invalid

    /// "2500", "2500,5", "2500.50", "₺ 2 500,00" kabul edilir; binlik noktası ("2.500") belirsiz olduğundan reddedilir.
    static func parse(_ text: String) -> BillAmountInput {
        let compact = text
            .replacingOccurrences(of: "₺", with: "")
            .replacingOccurrences(of: "TL", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return .empty }
        let normalized = compact.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              let integer = parts.first,
              (1...8).contains(integer.count),
              integer.allSatisfy(Self.isDigit) else {
            return .invalid
        }
        if parts.count == 2 {
            let fraction = parts[1]
            guard (1...2).contains(fraction.count), fraction.allSatisfy(Self.isDigit) else { return .invalid }
        }
        return .valid(normalized)
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

/// Servisi tamamlarken (Kalktı) ön ödeme dahil toplam hesabı sorar; alan boş bırakılabilir.
struct ServiceCloseSheet: View {
    let reservation: Reservation
    /// Normalize edilmiş tutarla (veya `nil`) kaydeder; başarılıysa `nil`, değilse gösterilecek hata döner.
    let onConfirm: (String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var parsed: BillAmountInput { BillAmountInput.parse(amountText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        MPAvatar(name: reservation.displayName, size: 44, tone: .info)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reservation.displayName)
                                .font(.headline)
                                .foregroundStyle(Color(.label))
                                .lineLimit(1)
                            Text("\(reservation.tableSummary) · \(reservation.guestText)")
                                .font(.subheadline)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)

                    Text(ServiceAction.left.confirmationMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        MPSectionHeader(title: "Toplam hesap", systemImage: "turkishlirasign", detail: "İsteğe bağlı")
                        HStack(spacing: 8) {
                            TextField("Örn. 2500,50", text: $amountText)
                                .keyboardType(.decimalPad)
                                .focused($isFocused)
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .accessibilityLabel("Toplam hesap, Türk lirası")
                            Text("₺")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .accessibilityHidden(true)
                        }
                        .mpCard(padding: 14)
                        .overlay {
                            if parsed == .invalid {
                                RoundedRectangle(cornerRadius: MP.radius, style: .continuous)
                                    .strokeBorder(MP.critical.opacity(0.6), lineWidth: 1.5)
                            }
                        }

                        if parsed == .invalid {
                            Label("Tutarı en fazla iki ondalık basamakla girin. Örnek: 2500,50", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(MP.critical)
                        } else {
                            Text("Ön ödeme dahil toplam tutar. Boş bırakılırsa hesap bilinmiyor olarak kalır.")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage {
                        MPNotice(message: errorMessage)
                    }
                }
                .padding(.horizontal, MP.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MP.background)
            .navigationTitle("Servisi tamamla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isFocused = false
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(MP.onBrand)
                        } else {
                            Image(systemName: ServiceAction.left.symbol)
                        }
                        Text(isSubmitting ? "Kaydediliyor…" : "Kalktı olarak kaydet")
                    }
                }
                .buttonStyle(MPPrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSubmitting)
    }

    private var canSubmit: Bool { parsed != .invalid && !isSubmitting }

    private func submit() async {
        let amount: String?
        switch parsed {
        case .empty: amount = nil
        case .valid(let value): amount = value
        case .invalid: return
        }
        isSubmitting = true
        errorMessage = nil
        let failure = await onConfirm(amount)
        isSubmitting = false
        if let failure {
            errorMessage = failure
        } else {
            dismiss()
        }
    }
}
