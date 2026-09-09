import SwiftUI

// MARK: - Tokens

enum MP {
    // Marka: uygulama ikonundaki lacivert/slate ailesi.
    static let navy = Color(red: 0.176, green: 0.216, blue: 0.282)      // #2D3748
    static let navyDeep = Color(red: 0.106, green: 0.129, blue: 0.176)  // #1B2130
    static let navySoft = Color(red: 0.290, green: 0.337, blue: 0.408)  // #4A5668
    static let steel = Color(red: 0.74, green: 0.80, blue: 0.89)

    /// Etkileşim rengi: açık modda lacivert, koyu modda açık çelik.
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

    /// Hero yüzeyler her iki temada da lacivert kalır.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [navySoft, navy, navyDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static let onHero = Color.white
    static let onHeroSecondary = Color.white.opacity(0.72)
    static let onHeroTertiary = Color.white.opacity(0.5)
    static let heroFill = Color.white.opacity(0.12)
    static let heroCritical = Color(red: 1.0, green: 0.48, blue: 0.45)
    static let heroPositive = Color(red: 0.42, green: 0.86, blue: 0.58)
    static let heroAttention = Color(red: 1.0, green: 0.72, blue: 0.36)

    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemGroupedBackground)
    static let separator = Color(.separator)
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
    })
    static let shadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor.black.withAlphaComponent(0.06)
    })

    static let positive = Color(.systemGreen)
    static let attention = Color(.systemOrange)
    static let critical = Color(.systemRed)
    static let info = Color(.systemBlue)

    static let radius: CGFloat = 18
    static let radiusSmall: CGFloat = 12
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

    /// Hero (lacivert) yüzey üzerinde okunur karşılığı.
    var heroColor: Color {
        switch self {
        case .positive: MP.heroPositive
        case .attention: MP.heroAttention
        case .critical: MP.heroCritical
        case .info: MP.steel
        case .brand, .neutral: MP.onHero
        }
    }

    /// Dolgu rengi olarak kullanıldığında ana renk (nötr için marka).
    var accent: Color { self == .neutral ? MP.brand : color }
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

/// Beyaz kutu içinde marka işareti; hero ve giriş ekranında.
struct MPBrandTile: View {
    var size: CGFloat = 36

    var body: some View {
        MPBrandMark(size: size * 0.7)
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

// MARK: - Cards

struct MPCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MP.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MP.hairline, lineWidth: 1)
            }
            .shadow(color: MP.shadow, radius: 10, y: 3)
    }
}

extension View {
    func mpCard(padding: CGFloat = 16, radius: CGFloat = MP.radius) -> some View {
        modifier(MPCardModifier(padding: padding, radius: radius))
    }

    /// Liste satırlarına özel bileşen yerleştirirken varsayılan arka planı ve kenar boşluğunu kaldırır.
    func mpPlainRow(vertical: CGFloat = 0, horizontal: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tone.color)
        .background(tone.color.opacity(0.13), in: Capsule())
    }
}

/// Küçük etiket: masa adı, kod gibi kısa bilgiler.
struct MPTag: View {
    let text: String
    var tone: MPTone = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tone == .neutral ? Color(.label) : tone.color)
        .background(tone == .neutral ? MP.fill : tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Identity

/// Baş harflerden avatar.
struct MPAvatar: View {
    let name: String
    var size: CGFloat = 40
    var tone: MPTone = .brand

    var body: some View {
        Text(Self.initials(from: name))
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(tone.accent)
            .frame(width: size, height: size)
            .background(tone.accent.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap(\.first).map(String.init)
        let joined = letters.joined().uppercased(with: Locale(identifier: "tr_TR"))
        return joined.isEmpty ? "?" : joined
    }
}

/// Renkli kutu içinde SF sembolü.
struct MPIconTile: View {
    let systemImage: String
    var tone: MPTone = .brand
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tone.accent)
            .frame(width: size, height: size)
            .background(tone.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Layout helpers

/// Saat + alt bilgi bloğu; listelerde göz sabit kolonu taramaya alışır.
struct MPTimeBlock: View {
    let time: String
    var caption: String? = nil
    var tone: MPTone = .neutral

    var body: some View {
        VStack(spacing: 1) {
            Text(time)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? Color(.label) : tone.color)
            if let caption {
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tone == .neutral ? Color(.secondaryLabel) : tone.color.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(width: 58, height: 48)
        .background(
            tone == .neutral ? MP.fill : tone.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Takvim yaprağı: gün numarası + ay.
struct MPDateLeaf: View {
    let day: String
    let month: String
    var tone: MPTone = .neutral

    var body: some View {
        VStack(spacing: 0) {
            Text(day)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? Color(.label) : tone.color)
            Text(month.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tone == .neutral ? Color(.secondaryLabel) : tone.color.opacity(0.85))
        }
        .frame(width: 54, height: 54)
        .background(
            tone == .neutral ? MP.fill : tone.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

struct MPSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var detail: String? = nil
    var tone: MPTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.accent)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.label))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Liste bölüm başlığı: renkli nokta/simge + başlık + sayı.
struct MPListSectionHeader: View {
    let title: String
    let count: Int
    var tone: MPTone = .neutral

    var body: some View {
        HStack(spacing: 7) {
            if tone != .neutral {
                Circle().fill(tone.color).frame(width: 7, height: 7)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
            Text(count, format: .number)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .textCase(nil)
    }
}

struct MPStatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    var tone: MPTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPIconTile(systemImage: systemImage, tone: tone, size: 30)
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
        .mpCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Kart içinde yan yana küçük metrik.
struct MPMetric: View {
    let value: String
    let label: String
    var tone: MPTone = .neutral
    var onHero = false

    init(value: String, label: String, tone: MPTone = .neutral, onHero: Bool = false) {
        self.value = value
        self.label = label
        self.tone = tone
        self.onHero = onHero
    }

    init(value: Int, label: String, tone: MPTone = .neutral, onHero: Bool = false) {
        self.init(value: value.formatted(), label: label, tone: tone, onHero: onHero)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(onHero ? MP.onHeroSecondary : Color(.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var valueColor: Color {
        if onHero { return tone == .neutral || tone == .brand ? MP.onHero : tone.heroColor }
        return tone == .neutral ? Color(.label) : tone.color
    }
}

/// Halka ilerleme göstergesi.
struct MPProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6
    var tone: MPTone = .positive
    var track: Color = MP.fill

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tone.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.5), value: progress)
        }
        .accessibilityHidden(true)
    }
}

/// İnce yatay ilerleme çubuğu.
struct MPBar: View {
    let progress: Double
    var tone: MPTone = .positive
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MP.fill)
                Capsule()
                    .fill(tone.accent)
                    .frame(width: max(height, proxy.size.width * min(max(progress, 0), 1)))
                    .animation(.snappy(duration: 0.4), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Kayan seçim kapsülü olan segment çubuğu.
struct MPSegment<Item: Hashable>: Identifiable {
    let id: Item
    let title: String
    var count: Int? = nil
}

struct MPSegmentBar<Item: Hashable>: View {
    let segments: [MPSegment<Item>]
    @Binding var selection: Item
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let isSelected = segment.id == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = segment.id }
                } label: {
                    HStack(spacing: 5) {
                        Text(segment.title)
                        if let count = segment.count {
                            Text(count, format: .number)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? MP.onBrand.opacity(0.7) : Color(.tertiaryLabel))
                        }
                    }
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(MP.brand)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(MP.fill, in: Capsule())
    }
}

// MARK: - Operations visuals

struct MPHourlyLoadBucket: Identifiable, Equatable {
    let hour: Int
    let guests: Int
    let reservations: Int

    var id: Int { hour }
}

/// Saat bazında misafir yoğunluğu çubukları.
struct MPHourlyLoad: View {
    let buckets: [MPHourlyLoadBucket]
    let currentHour: Int
    var barHeight: CGFloat = 56

    var body: some View {
        let peak = max(1, buckets.map(\.guests).max() ?? 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(buckets) { bucket in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: bucket))
                        .frame(height: max(4, CGFloat(bucket.guests) / CGFloat(peak) * barHeight))
                        .frame(maxWidth: .infinity, maxHeight: barHeight, alignment: .bottom)
                        .accessibilityLabel("\(bucket.hour):00, \(bucket.guests) kişi")
                }
            }
            HStack(spacing: 3) {
                ForEach(buckets) { bucket in
                    Text(labelText(for: bucket))
                        .font(.system(size: 9, weight: bucket.hour == currentHour ? .bold : .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(bucket.hour == currentHour ? MP.brand : Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func color(for bucket: MPHourlyLoadBucket) -> Color {
        if bucket.guests == 0 { return MP.fill }
        if bucket.hour == currentHour { return MP.brand }
        if bucket.hour < currentHour { return MP.brand.opacity(0.3) }
        return MP.brand.opacity(0.62)
    }

    private func labelText(for bucket: MPHourlyLoadBucket) -> String {
        let step = buckets.count <= 8 ? 1 : (buckets.count <= 16 ? 2 : 4)
        let isCurrent = bucket.hour == currentHour
        let isNeighborOfCurrent = abs(bucket.hour - currentHour) == 1 && step > 1
        guard isCurrent || (bucket.hour % step == 0 && !isNeighborOfCurrent) else { return "" }
        return String(format: "%02d", bucket.hour)
    }
}

extension VenueTable {
    enum FloorState {
        case empty, occupied, bill, cleaning

        var tone: MPTone {
            switch self {
            case .empty: .neutral
            case .occupied: .positive
            case .bill: .attention
            case .cleaning: .info
            }
        }

        var title: String {
            switch self {
            case .empty: "Boş"
            case .occupied: "Dolu"
            case .bill: "Hesap"
            case .cleaning: "Temizlik"
            }
        }
    }

    var floorState: FloorState {
        switch (serviceStatus ?? "").uppercased() {
        case "ARRIVED", "SEATED": .occupied
        case "BILL": .bill
        case "CLEANING": .cleaning
        default: .empty
        }
    }
}

/// Salon durumunda tek masa.
struct MPTableChip: View {
    let table: VenueTable

    var body: some View {
        let tone = table.floorState.tone
        VStack(spacing: 2) {
            Text(table.name)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(tone == .neutral ? Color(.label) : tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                Image(systemName: "person.fill").font(.system(size: 8))
                Text(table.capacity, format: .number)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(tone == .neutral ? Color(.tertiaryLabel) : tone.color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            tone == .neutral ? MP.fill : tone.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tone == .neutral ? MP.hairline : tone.color.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Masa \(table.name), \(table.capacity) kişilik, \(table.floorState.title)")
    }
}

/// Bugün ekranındaki hızlı eylem kutusu.
struct MPQuickActionLabel: View {
    let title: String
    let systemImage: String
    var tone: MPTone = .brand
    var badge: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MPIconTile(systemImage: systemImage, tone: tone, size: 40)
                if let badge, badge > 0 {
                    Text(badge, format: .number)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(MP.critical, in: Capsule())
                        .offset(x: 7, y: -6)
                }
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .mpCard(padding: 0, radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .overlay {
            RoundedRectangle(cornerRadius: MP.radius, style: .continuous)
                .strokeBorder(tone.color.opacity(0.2), lineWidth: 1)
        }
    }
}

struct MPEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MP.brand)
                .frame(width: 52, height: 52)
                .background(MP.brand.opacity(0.1), in: Circle())
                .padding(.bottom, 2)
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
    var onHero = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? MP.positive : MP.attention)
                .frame(width: 6, height: 6)
            Text(isConnected ? "Canlı" : "Bağlanıyor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(onHero ? MP.onHeroSecondary : Color(.secondaryLabel))
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(onHero ? MP.heroFill : MP.fill, in: Capsule())
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
            .frame(height: 52)
            .background(tone.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
            .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Satır içi küçük eylem: "Geldi", "Teklif".
struct MPCompactButtonStyle: ButtonStyle {
    var tone: MPTone = .brand
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(filled ? (tone == .brand ? MP.onBrand : Color.white) : tone.color)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(filled ? tone.color : tone.color.opacity(0.12), in: Capsule())
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
            .padding(.horizontal, 13)
            .frame(height: 34)
            .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
            .background(isSelected ? MP.brand : MP.fill, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(MP.hairline, lineWidth: 1)
                }
            }
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
    var hasNote: Bool { !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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

    var sectionTone: MPTone {
        switch self {
        case .overdue: .critical
        case .now: .info
        case .upcoming: .neutral
        case .inside: .positive
        case .pending: .attention
        case .later, .terminal: .neutral
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
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMM EEE"
        return formatter
    }()

    static let istanbulCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.locale = Locale(identifier: "tr_TR")
        return calendar
    }()

    private static let apiDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fullDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMMM yyyy, EEEE"
        return formatter
    }()

    /// API'den gelen `yyyy-MM-dd` tarihini okunur biçime çevirir.
    static func displayDate(_ apiDate: String) -> String {
        guard let date = apiDay.date(from: apiDate) else { return apiDate }
        return fullDay.string(from: date)
    }

    /// Saate göre selamlama.
    static func greeting(for date: Date = .now, name: String?) -> String {
        let hour = istanbulCalendar.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<12: base = "Günaydın"
        case 12..<17: base = "İyi günler"
        case 17..<23: base = "İyi akşamlar"
        default: base = "İyi geceler"
        }
        guard let name, !name.isEmpty else { return base }
        return "\(base), \(name)"
    }
}
