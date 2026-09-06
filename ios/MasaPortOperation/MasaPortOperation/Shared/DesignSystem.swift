import SwiftUI

// MARK: - Tokens

enum MP {
    /// Marka rengi: uygulama ikonundaki lacivert/slate. Koyu modda açık çelik tonuna döner.
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.80, blue: 0.89, alpha: 1)
            : UIColor(red: 0.176, green: 0.216, blue: 0.282, alpha: 1)
    })
    /// Marka dolgusu üzerindeki metin rengi.
    static let onBrand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1)
            : .white
    })

    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemGroupedBackground)
    static let separator = Color(.separator)

    static let positive = Color(.systemGreen)
    static let attention = Color(.systemOrange)
    static let critical = Color(.systemRed)
    static let info = Color(.systemBlue)

    static let radius: CGFloat = 14
    static let gutter: CGFloat = 16
}

enum MPTone: Equatable {
    case positive, attention, critical, info, brand, neutral

    var color: Color {
        switch self {
        case .positive: MP.positive
        case .attention: MP.attention
        case .critical: MP.critical
        case .info: MP.info
        case .brand: MP.brand
        case .neutral: Color(.secondaryLabel)
        }
    }
}

struct MPStatus: Equatable {
    let text: String
    let tone: MPTone
}

// MARK: - Brand

struct MPBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("MasaPortMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Küçük renkli nokta + metin. Liste satırlarında rozet yerine kullanılır.
struct MPStatusLabel: View {
    let status: MPStatus
    var emphasized = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tone.color)
                .frame(width: 7, height: 7)
            Text(status.text)
                .font(.footnote.weight(emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? status.tone.color : Color(.secondaryLabel))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Yumuşak dolgulu kapsül. Detay başlıklarında ve özetlerde kullanılır.
struct MPPill: View {
    let text: String
    let tone: MPTone

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(0.13), in: Capsule())
    }
}

// MARK: - Layout helpers

/// Sabit genişlikli saat kolonu: listelerde göz saati taramaya alışır.
struct MPTimeColumn: View {
    let time: String
    var caption: String? = nil
    var tone: MPTone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone?.color ?? Color(.label))
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(width: 54, alignment: .leading)
    }
}

struct MPStatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    var tone: MPTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone == .neutral ? MP.brand : tone.color)
                .frame(width: 28, height: 28)
                .background((tone == .neutral ? MP.brand : tone.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value, format: .number)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tone == .critical && value > 0 ? MP.critical : Color(.label))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct MPSectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.label))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, 4)
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

    /// Liste satırlarına özel bileşen yerleştirirken varsayılan arka planı ve kenar boşluğunu kaldırır.
    func mpPlainRow(vertical: CGFloat = 0, horizontal: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Feedback

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
                    .foregroundStyle(Color(.label))
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

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.bottom, 4)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
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

/// Canlı bağlantı göstergesi.
struct MPLiveIndicator: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? MP.positive : MP.attention)
                .frame(width: 6, height: 6)
            Text(isConnected ? "Canlı" : "Bağlanıyor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(MP.fill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isConnected ? "Canlı bağlantı kuruldu" : "Canlı bağlantı kuruluyor")
    }
}

// MARK: - Buttons

struct MPPrimaryButtonStyle: ButtonStyle {
    var tone: MPTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tone == .brand ? MP.onBrand : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(tone.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .frame(height: 44)
            .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Satır içi küçük eylem: "Geldi", "Teklif".
struct MPCompactButtonStyle: ButtonStyle {
    var tone: MPTone = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(tone.color.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Filtre çipi.
struct MPFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? MP.onBrand.opacity(0.75) : Color(.tertiaryLabel))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
            .background(isSelected ? MP.brand : MP.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Reservation presentation

extension Reservation {
    var displayName: String { customerName.isEmpty ? "Misafir" : customerName }
    var shortTime: String { String(startTime.prefix(5)) }
    var timeRange: String { "\(startTime.prefix(5))–\(endTime.prefix(5))" }
    var tableSummary: String {
        let names = tables.map(\.name).joined(separator: ", ")
        return names.isEmpty ? "Masa atanmadı" : names
    }
    var hasTable: Bool { !tables.isEmpty }
    var guestText: String { "\(guestCount) kişi" }

    var reservationTone: MPTone {
        if checkedIn { return .positive }
        switch status.uppercased() {
        case "CONFIRMED": return .positive
        case "PENDING": return .attention
        case "CANCELLED", "NO_SHOW": return .critical
        default: return .neutral
        }
    }

    var canCheckIn: Bool {
        status.uppercased() == "CONFIRMED" && !checkedIn
    }

    func operationBadge(relativeTo referenceDate: Date = .now) -> MPStatus {
        switch operationalState(relativeTo: referenceDate) {
        case .inside:
            return MPStatus(text: serviceStatus?.localizedServiceStatus ?? "İçeride", tone: .positive)
        case .overdue(let minutes):
            return minutes <= 180
                ? MPStatus(text: "\(minutes) dk gecikti", tone: .critical)
                : MPStatus(text: "Gelmedi", tone: .critical)
        case .now:
            return MPStatus(text: "Şimdi", tone: .info)
        case .upcoming(let minutes):
            return MPStatus(text: "\(minutes) dk sonra", tone: .info)
        case .pending:
            return MPStatus(text: "Onay bekliyor", tone: .attention)
        case .later:
            return MPStatus(text: status.localizedReservationStatus, tone: .neutral)
        case .terminal:
            return MPStatus(text: status.localizedReservationStatus, tone: reservationTone == .critical ? .critical : .neutral)
        }
    }
}

extension ReservationOperationalState {
    /// Host Masası'nda satırların gruplandığı bölüm.
    var sectionTitle: String {
        switch self {
        case .overdue: "Geciken"
        case .now: "Şimdi"
        case .upcoming: "Sıradaki"
        case .inside: "İçeride"
        case .pending: "Onay bekleyen"
        case .later: "Daha sonra"
        case .terminal: "Tamamlanan"
        }
    }

    var sectionOrder: Int {
        switch self {
        case .overdue: 0
        case .now: 1
        case .upcoming: 2
        case .inside: 3
        case .pending: 4
        case .later: 5
        case .terminal: 6
        }
    }
}

enum MPDateFormat {
    static let longDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMMM EEEE"
        return formatter
    }()
}
