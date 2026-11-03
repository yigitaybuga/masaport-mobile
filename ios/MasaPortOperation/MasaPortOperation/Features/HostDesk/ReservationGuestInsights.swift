import SwiftUI

/// API sözlüğüyle aynı anahtarlar (`api.masaport/src/utils/reservationGuestDetails.js`). Sunucu `guest_details`
/// göndermediğinde ham `occasion` / `guestPreferences` anahtarlarından etiket üretmek için kullanılır.
enum GuestPreferenceCatalog {
    static let occasions: [String: String] = [
        "birthday": "Doğum günü",
        "anniversary": "Yıl dönümü",
        "date_night": "Romantik akşam",
        "business": "İş yemeği",
        "celebration": "Kutlama"
    ]

    static let dietaryOrder = ["vegetarian", "vegan", "gluten_free", "lactose_free", "nut_allergy", "seafood_allergy", "halal", "no_alcohol"]
    static let dietary: [String: String] = [
        "vegetarian": "Vejetaryen",
        "vegan": "Vegan",
        "gluten_free": "Glütensiz",
        "lactose_free": "Laktozsuz",
        "nut_allergy": "Kuruyemiş alerjisi",
        "seafood_allergy": "Deniz ürünü alerjisi",
        "halal": "Helal",
        "no_alcohol": "Alkolsüz"
    ]

    static let seatingOrder = ["window", "outdoor", "indoor", "quiet", "bar", "accessible", "high_chair"]
    static let seating: [String: String] = [
        "window": "Pencere kenarı",
        "outdoor": "Dış mekân",
        "indoor": "İç mekân",
        "quiet": "Sessiz köşe",
        "bar": "Bar",
        "accessible": "Erişilebilir masa",
        "high_chair": "Mama sandalyesi"
    ]

    /// Mutfağa mutlaka iletilmesi gereken kısıtlar.
    static let allergyKeys: Set<String> = ["nut_allergy", "seafood_allergy", "gluten_free", "lactose_free"]

    static func labels(for keys: [String], order: [String], catalog: [String: String]) -> [String] {
        let picked = Set(keys.map { $0.lowercased() })
        return order.filter(picked.contains).compactMap { catalog[$0] }
    }
}

enum ReservationVIPLevel: String {
    case silver = "SILVER"
    case gold = "GOLD"
    case platinum = "PLATINUM"

    var title: String {
        switch self {
        case .silver: "Gümüş"
        case .gold: "Altın"
        case .platinum: "Platin"
        }
    }

    var longTitle: String { "\(title) misafir" }
}

/// Satır ve detayda gösterilen tek bir misafir işareti; renk her zaman metin ve sembolle birlikte kullanılır.
struct ReservationInsight: Identifiable, Equatable {
    enum Kind: String {
        case allergy, arrival, vip, occasion, noShow, dietary, seating
    }

    let kind: Kind
    let text: String
    let systemImage: String
    let tone: MPTone
    /// VoiceOver için daha açık ifade.
    let spokenText: String

    var id: String { kind.rawValue }
}

extension Reservation {
    var occasionKey: String? {
        guestDetails?.occasion ?? occasion?.lowercased()
    }

    var occasionLabel: String? {
        if let label = guestDetails?.occasionLabel { return label }
        return occasionKey.flatMap { GuestPreferenceCatalog.occasions[$0] }
    }

    /// Diyet/alerji etiketleri (alerjiler dahil).
    var dietaryLabels: [String] {
        if let details = guestDetails { return details.dietary }
        return GuestPreferenceCatalog.labels(
            for: guestPreferences?.dietary ?? [],
            order: GuestPreferenceCatalog.dietaryOrder,
            catalog: GuestPreferenceCatalog.dietary
        )
    }

    var allergyLabels: [String] {
        if let details = guestDetails { return details.allergies }
        let keys = (guestPreferences?.dietary ?? []).filter { GuestPreferenceCatalog.allergyKeys.contains($0.lowercased()) }
        return GuestPreferenceCatalog.labels(for: keys, order: GuestPreferenceCatalog.dietaryOrder, catalog: GuestPreferenceCatalog.dietary)
    }

    /// Alerji olmayan diyet tercihleri (vegan, helal…).
    var otherDietaryLabels: [String] {
        let allergies = Set(allergyLabels)
        return dietaryLabels.filter { !allergies.contains($0) }
    }

    var seatingLabels: [String] {
        if let details = guestDetails { return details.seating }
        return GuestPreferenceCatalog.labels(
            for: guestPreferences?.seating ?? [],
            order: GuestPreferenceCatalog.seatingOrder,
            catalog: GuestPreferenceCatalog.seating
        )
    }

    /// Sayı misafirin tüm gelmemelerini içerir; bu kayıt da "gelmedi" ise kendisi düşülür.
    var previousNoShowCount: Int {
        max(0, (noShowCount ?? 0) - (status.uppercased() == "NO_SHOW" ? 1 : 0))
    }

    var vipLevel: ReservationVIPLevel? {
        vipTier.flatMap { ReservationVIPLevel(rawValue: $0.uppercased()) }
    }

    var arrivalNoteText: String? {
        let trimmed = (arrivalNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Misafirin "N dakika gecikeceğim" yanıtındaki dakika.
    var arrivalDelayMinutes: Int? {
        guard let note = arrivalNoteText, let range = note.range(of: " dakika gecik") else { return nil }
        let digits = String(note[..<range.lowerBound].reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        return Int(digits)
    }

    /// Geliş teyidi rozeti; gelmiş, kapanmış veya teyit beklenmeyen kayıtta gösterilmez.
    var arrivalIndicator: ReservationInsight? {
        guard !checkedIn, !isTerminal else { return nil }
        switch arrivalStatus?.uppercased() {
        case "NOTIFIED":
            let isGuestComing = arrivalStatusBy == nil && (arrivalNoteText?.contains("Geliyorum") ?? false)
            return isGuestComing
                ? ReservationInsight(kind: .arrival, text: "Geliyorum", systemImage: "hand.thumbsup.fill", tone: .positive, spokenText: "Misafir geleceğini teyit etti")
                : ReservationInsight(kind: .arrival, text: "Haber verdi", systemImage: "bubble.left.fill", tone: .info, spokenText: "Misafir haber verdi")
        case "LATE":
            if let minutes = arrivalDelayMinutes {
                return ReservationInsight(kind: .arrival, text: "\(minutes) dk gecikecek", systemImage: "clock.badge.exclamationmark", tone: .attention, spokenText: "Misafir \(minutes) dakika gecikeceğini bildirdi")
            }
            return ReservationInsight(kind: .arrival, text: "Gecikti", systemImage: "clock.badge.exclamationmark", tone: .attention, spokenText: "Gecikti olarak işaretli")
        default:
            return nil
        }
    }

    /// Karşılama önceliğine göre: alerji, geliş teyidi, VIP, özel gün, gelmeme geçmişi, diyet, oturma.
    var insights: [ReservationInsight] {
        var items: [ReservationInsight] = []
        let allergies = allergyLabels
        if !allergies.isEmpty {
            let text = allergies.joined(separator: ", ")
            items.append(ReservationInsight(kind: .allergy, text: text, systemImage: "exclamationmark.triangle.fill", tone: .critical, spokenText: "Alerji: \(text)"))
        }
        if let arrival = arrivalIndicator {
            items.append(arrival)
        }
        if let vip = vipLevel {
            items.append(ReservationInsight(kind: .vip, text: vip.title, systemImage: "star.fill", tone: .brand, spokenText: vip.longTitle))
        }
        if let occasion = occasionLabel {
            items.append(ReservationInsight(kind: .occasion, text: occasion, systemImage: Self.occasionSymbol(occasionKey), tone: .info, spokenText: "Özel gün: \(occasion)"))
        }
        let noShows = previousNoShowCount
        if noShows > 0 {
            items.append(ReservationInsight(kind: .noShow, text: "\(noShows) kez gelmedi", systemImage: "person.fill.xmark", tone: .critical, spokenText: "Daha önce \(noShows) kez gelmedi"))
        }
        let dietary = otherDietaryLabels
        if !dietary.isEmpty {
            let text = dietary.joined(separator: ", ")
            items.append(ReservationInsight(kind: .dietary, text: text, systemImage: "leaf.fill", tone: .neutral, spokenText: "Diyet: \(text)"))
        }
        let seating = seatingLabels
        if !seating.isEmpty {
            let text = seating.joined(separator: ", ")
            items.append(ReservationInsight(kind: .seating, text: text, systemImage: "chair.fill", tone: .neutral, spokenText: "Oturma tercihi: \(text)"))
        }
        return items
    }

    static func occasionSymbol(_ key: String?) -> String {
        switch key {
        case "birthday": "birthday.cake.fill"
        case "anniversary", "date_night": "heart.fill"
        case "business": "briefcase.fill"
        default: "party.popper.fill"
        }
    }
}

// MARK: - Row tags

/// Satırda ilk bakışta görülmesi gereken misafir işaretleri; sığmayanlar "+N" olarak özetlenir.
struct ReservationInsightTags: View {
    let insights: [ReservationInsight]
    var limit = 3

    var body: some View {
        let visible = Array(insights.prefix(limit))
        let hiddenCount = insights.count - visible.count
        InsightFlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(visible) { insight in
                MPTag(text: insight.text, tone: insight.tone, systemImage: insight.systemImage)
            }
            if hiddenCount > 0 {
                MPTag(text: "+\(hiddenCount)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insights.map(\.spokenText).joined(separator: ", "))
    }
}

/// Etiketleri satırlara saran basit akış yerleşimi.
struct InsightFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // Uzun etiket tek satıra kısaltılır.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (frames, CGSize(width: width, height: y + rowHeight))
    }
}

// MARK: - Detail card

/// Rezervasyon detayında misafir bilgisi: geliş teyidi, alerji/diyet, oturma, özel gün, VIP ve gelmeme geçmişi.
struct ReservationGuestInsightCard: View {
    let reservation: Reservation

    var body: some View {
        let rows = makeRows()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MPSectionHeader(
                    title: "Misafir bilgisi",
                    systemImage: "person.text.rectangle.fill",
                    tone: reservation.allergyLabels.isEmpty ? .neutral : .critical
                )
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, 56)
                        }
                        rowView(row)
                    }
                }
                .mpCard(padding: 0)
            }
        }
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let value: String
        var detail: String? = nil
        let systemImage: String
        let tone: MPTone
    }

    private func makeRows() -> [Row] {
        var rows: [Row] = []
        if let arrival = reservation.arrivalIndicator {
            rows.append(Row(id: "arrival", title: "Geliş teyidi", value: arrival.text, detail: reservation.arrivalNoteText, systemImage: arrival.systemImage, tone: arrival.tone))
        }
        let allergies = reservation.allergyLabels
        if !allergies.isEmpty {
            rows.append(Row(id: "allergy", title: "Alerji · mutfağa iletin", value: allergies.joined(separator: ", "), systemImage: "exclamationmark.triangle.fill", tone: .critical))
        }
        let dietary = reservation.otherDietaryLabels
        if !dietary.isEmpty {
            rows.append(Row(id: "dietary", title: "Diyet", value: dietary.joined(separator: ", "), systemImage: "leaf.fill", tone: .positive))
        }
        let seating = reservation.seatingLabels
        if !seating.isEmpty {
            rows.append(Row(id: "seating", title: "Oturma tercihi", value: seating.joined(separator: ", "), systemImage: "chair.fill", tone: .neutral))
        }
        if let occasion = reservation.occasionLabel {
            rows.append(Row(id: "occasion", title: "Özel gün", value: occasion, systemImage: Reservation.occasionSymbol(reservation.occasionKey), tone: .info))
        }
        if let vip = reservation.vipLevel {
            rows.append(Row(id: "vip", title: "Misafir seviyesi", value: vip.longTitle, systemImage: "star.fill", tone: .brand))
        }
        let noShows = reservation.previousNoShowCount
        if noShows > 0 {
            rows.append(Row(id: "noShow", title: "Gelmeme geçmişi", value: "Daha önce \(noShows) kez gelmedi", systemImage: "person.fill.xmark", tone: .critical))
        }
        return rows
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MPIconTile(systemImage: row.systemImage, tone: row.tone, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                Text(row.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(row.tone == .critical ? MP.critical : Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = row.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
