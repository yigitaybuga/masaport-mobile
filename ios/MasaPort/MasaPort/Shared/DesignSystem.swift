import SwiftUI

// MARK: - Tokens

enum MP {
    /// Marka rengi: Operasyon uygulamasıyla aynı lacivert/slate. Koyu modda açık çelik tonu.
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.80, blue: 0.89, alpha: 1)
            : UIColor(red: 0.176, green: 0.216, blue: 0.282, alpha: 1)
    })
    static let onBrand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1)
            : .white
    })
    /// Ana aksiyon butonları (Müsait masaları gör, Rezervasyon yap, Bilet al, Giriş yap): masaport.com kırmızısı.
    /// Sekmeler, çipler ve rozetler `brand` tonunda kalır; yalnızca `.glassProminent` CTA'lar bu rengi alır.
    static let action = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.878, green: 0.227, blue: 0.251, alpha: 1)
            : UIColor(red: 0.714, green: 0.090, blue: 0.118, alpha: 1)
    })

    /// Sıcak vurgu: müsait saat çipleri ve "bu akşam" rozetleri.
    static let warm = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.72, blue: 0.45, alpha: 1)
            : UIColor(red: 0.80, green: 0.42, blue: 0.16, alpha: 1)
    })

    static let placeholderTop = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
            : UIColor(red: 0.62, green: 0.68, blue: 0.78, alpha: 1)
    })
    static let placeholderBottom = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : UIColor(red: 0.40, green: 0.46, blue: 0.56, alpha: 1)
    })
    static let placeholderSymbol = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.22)
            : UIColor(white: 1, alpha: 0.55)
    })

    static let background = Color(.systemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemBackground)
    static let fill = Color(.tertiarySystemFill)

    static let positive = Color(.systemGreen)
    static let attention = Color(.systemOrange)
    static let critical = Color(.systemRed)

    static let radius: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let gutter: CGFloat = 20
}

enum MPTone {
    case brand, warm, positive, attention, critical, neutral

    var color: Color {
        switch self {
        case .brand: MP.brand
        case .warm: MP.warm
        case .positive: MP.positive
        case .attention: MP.attention
        case .critical: MP.critical
        case .neutral: Color(.secondaryLabel)
        }
    }
}

// MARK: - Görseller

/// Uzak görsel: yükleme sırasında yumuşak gradyan, hata durumunda sembol.
struct MPRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol = "fork.knife"
    var role: MPImageRole = .card

    var body: some View {
        Color.clear
            .overlay {
                if let url = MPImageURL.variantURL(for: url, role: role) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: contentMode)
                        case .failure:
                            placeholder
                        case .empty:
                            placeholder.overlay { ProgressView().tint(.white.opacity(0.8)) }
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
    }

    private var placeholder: some View {
        ZStack {
            // Açık modda yumuşak lacivert, koyu modda mat çelik: iki görünümde de görsel kadar parlamaz.
            LinearGradient(colors: [MP.placeholderTop, MP.placeholderBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: placeholderSymbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(MP.placeholderSymbol)
        }
    }
}

/// Uygulama ikonuyla aynı dilde marka işareti: lacivert kart üstünde açık işaret.
/// Her iki görünümde de aynı kalır; koyu modda siyah zeminde kaybolmaz.
struct MPBrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.243, green: 0.290, blue: 0.372), Color(red: 0.118, green: 0.145, blue: 0.196)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image("MasaPortMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(red: 0.90, green: 0.93, blue: 0.97))
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Rozetler ve çipler

/// Görsel üstünde duran cam rozet.
struct MPGlassBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint == nil ? Color.primary : Color.white)
        .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .capsule)
    }
}

struct MPPill: View {
    let text: String
    var tone: MPTone = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(tone == .neutral ? Color(.secondaryLabel) : tone.color)
        .background((tone == .neutral ? Color(.secondaryLabel) : tone.color).opacity(0.12), in: Capsule())
    }
}

/// Seçilebilir filtre çipi.
struct MPChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.footnote.weight(.semibold))
                }
                Text(title).font(.subheadline.weight(.medium))
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(isSelected ? MP.onBrand : Color.primary)
            .background(isSelected ? MP.brand : MP.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Müsait saat çipi: ana rezervasyon tetikleyicisi.
struct MPTimeChip: View {
    let time: String
    var isSelected = false
    var isEnabled = true
    var caption: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(time)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 68)
            .frame(height: caption == nil ? 40 : 48)
            .foregroundStyle(isSelected ? MP.onBrand : (isEnabled ? MP.brand : Color(.tertiaryLabel)))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MP.brand)
                } else if isEnabled {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MP.brand.opacity(0.10))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MPRatingLabel: View {
    let rating: Double?
    var count: Int? = nil

    var body: some View {
        if let text = Format.rating(rating) {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MP.warm)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let count, count > 0 {
                    Text("(\(count))")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Puan \(text)")
        }
    }
}

// MARK: - Bölümler ve kartlar

struct MPSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .tint(MP.brand)
            }
        }
        .padding(.horizontal, MP.gutter)
    }
}

struct MPCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
    }
}

extension View {
    func mpCard(padding: CGFloat = 16) -> some View {
        modifier(MPCardModifier(padding: padding))
    }

    func mpPlainRow(vertical: CGFloat = 0, horizontal: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Butonlar

struct MPPrimaryButtonStyle: ButtonStyle {
    var tone: MPTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tone == .brand ? MP.onBrand : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(tone.color, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MPSecondaryButtonStyle: ButtonStyle {
    var tone: MPTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone.color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(tone.color.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Geri bildirim

struct MPNotice: View {
    let message: String
    var tone: MPTone = .critical
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(tone.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .tint(tone.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
    }
}

struct MPEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MP.brand.opacity(0.7))
                .padding(.bottom, 4)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 28)
    }
}

/// Yükleme iskeleti: içeriğin yerini tutan yumuşak bloklar.
struct MPSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var radius: CGFloat = 8

    @State private var phase = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(MP.fill)
            .frame(width: width, height: height)
            .opacity(phase ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = true }
            .accessibilityHidden(true)
    }
}

struct MPLoadingRow: View {
    var title = "Yükleniyor"

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Form yardımcıları

struct MPLabeledField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            content
                .font(.body)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(MP.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

struct MPStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...12
    var unit = "kişi"

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            HStack(spacing: 0) {
                Button {
                    value = max(range.lowerBound, value - 1)
                } label: {
                    Image(systemName: "minus").frame(width: 40, height: 36)
                }
                .disabled(value <= range.lowerBound)
                Text("\(value) \(unit)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 64)
                    .contentTransition(.numericText())
                Button {
                    value = min(range.upperBound, value + 1)
                } label: {
                    Image(systemName: "plus").frame(width: 40, height: 36)
                }
                .disabled(value >= range.upperBound)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(MP.brand)
            // Form/List satırında varsayılan stil tüm satırı tek buton gibi ele alır; iki buton ayrı ayrı basılabilsin.
            .buttonStyle(.borderless)
            .background(MP.fill, in: Capsule())
            .animation(.snappy, value: value)
        }
        .accessibilityElement(children: .contain)
    }
}


// MARK: - Hero üst çubuğu

/// Safe area'nın altına uzanan hero görselli sayfalarda, içerik kaydırıldığında
/// üstte materyal bir çubuk ve başlık belirir; böylece durum çubuğu ve araç çubuğu
/// görsellerin üstünde okunaklı kalır.
struct MPHeroTopBar: ViewModifier {
    let title: String
    let threshold: CGFloat

    @State private var collapsed = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, isCollapsed in
                withAnimation(.easeInOut(duration: 0.18)) { collapsed = isCollapsed }
            }
            .overlay(alignment: .top) {
                // İçerik safe area'yı yok saydığı için sistem araç çubuğu arka planı çizilmez;
                // durum çubuğu + araç çubuğu yüksekliğinde kendi materyal çubuğumuzu koyarız.
                if collapsed {
                    Rectangle()
                        .fill(.bar)
                        .frame(height: MPHeroTopBar.statusBarHeight + 44)
                        .overlay(alignment: .bottom) { Divider() }
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            // Görselin üstündeyken araç çubuğu ve durum çubuğu açık renk; çubuk belirince sisteme döner.
            .toolbarColorScheme(collapsed ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(collapsed ? 1 : 0)
                        .accessibilityHidden(!collapsed)
                }
            }
    }
}

extension MPHeroTopBar {
    @MainActor static var statusBarHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets.top ?? 54
    }
}

extension View {
    func mpHeroTopBar(title: String, threshold: CGFloat = 220) -> some View {
        modifier(MPHeroTopBar(title: title, threshold: threshold))
    }
}
