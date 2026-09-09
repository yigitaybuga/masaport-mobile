import SwiftUI
import WidgetKit

struct OperationSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: OperationWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                OperationWidgetMediumView(snapshot: entry.snapshot)
            } else {
                OperationWidgetSmallView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(for: .widget) {
            OperationWidgetDesign.heroGradient
        }
        .widgetURL(OperationWidgetConfiguration.todayURL)
    }
}

private struct OperationWidgetHeader: View {
    let venueName: String

    var body: some View {
        HStack(spacing: OperationWidgetDesign.standardSpacing) {
            Image("MasaPortMark")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: OperationWidgetDesign.markSize, height: OperationWidgetDesign.markSize)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text(venueName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct OperationWidgetSmallView: View {
    let snapshot: OperationWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: OperationWidgetDesign.standardSpacing) {
            OperationWidgetHeader(venueName: snapshot.venueName)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.reservationCount, format: .number)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(OperationWidgetDesign.onHero)
                    Text("rezervasyon")
                        .font(.caption)
                        .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                }
                Spacer(minLength: 0)
                if let expected = snapshot.expectedCount, expected > 0 {
                    ZStack {
                        OperationWidgetRing(progress: Double(snapshot.arrivedCount ?? 0) / Double(expected), lineWidth: 4)
                        Text(snapshot.arrivedCount ?? 0, format: .number)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(OperationWidgetDesign.onHero)
                    }
                    .frame(width: 36, height: 36)
                }
            }

            HStack(spacing: OperationWidgetDesign.sectionSpacing) {
                Label("\(snapshot.waitlistCount)", systemImage: "hourglass")
                    .foregroundStyle(snapshot.waitlistCount > 0 ? OperationWidgetDesign.heroAttention : OperationWidgetDesign.onHeroSecondary)
                Label("\(snapshot.overdueCount)", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(snapshot.overdueCount > 0 ? OperationWidgetDesign.heroCritical : OperationWidgetDesign.onHeroSecondary)
                if let tableCount = snapshot.tableCount, tableCount > 0 {
                    Label("\(snapshot.activeTableCount)/\(tableCount)", systemImage: "tablecells")
                        .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(OperationWidgetDesign.contentPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bugün \(snapshot.reservationCount) rezervasyon, \(snapshot.waitlistCount) bekleyen misafir, \(snapshot.overdueCount) geciken rezervasyon")
    }
}

private struct OperationWidgetMediumView: View {
    let snapshot: OperationWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: OperationWidgetDesign.standardSpacing) {
            HStack(spacing: OperationWidgetDesign.standardSpacing) {
                OperationWidgetHeader(venueName: snapshot.venueName)
                if snapshot.overdueCount > 0 {
                    Text("\(snapshot.overdueCount) geciken")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(OperationWidgetDesign.onHero)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(OperationWidgetDesign.heroCritical.opacity(0.85), in: Capsule())
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: OperationWidgetDesign.sectionSpacing) {
                if let expected = snapshot.expectedCount, expected > 0 {
                    ZStack {
                        OperationWidgetRing(progress: Double(snapshot.arrivedCount ?? 0) / Double(expected))
                        VStack(spacing: -2) {
                            Text(snapshot.arrivedCount ?? 0, format: .number)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(OperationWidgetDesign.onHero)
                            Text("/ \(expected)")
                                .font(.system(size: 8, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .accessibilityLabel("Karşılanan \(snapshot.arrivedCount ?? 0) / \(expected)")
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.reservationCount, format: .number)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(OperationWidgetDesign.onHero)
                    Text("rezervasyon bugün")
                        .font(.caption)
                        .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if let nextReservation = snapshot.nextReservation {
                        Text("SIRADAKİ")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                        Text(nextReservation.startTime)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(OperationWidgetDesign.onHero)
                        Text("\(nextReservation.guestCount) kişi")
                            .font(.caption)
                            .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                    } else {
                        Label("Sırada yok", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OperationWidgetDesign.onHeroSecondary)
                    }
                }
            }

            HStack(spacing: 0) {
                OperationWidgetMetric(value: snapshot.insideCount ?? snapshot.activeTableCount, label: "İçeride", tint: OperationWidgetDesign.heroPositive)
                OperationWidgetMetric(
                    value: snapshot.tableCount.map { "\(snapshot.activeTableCount)/\($0)" } ?? snapshot.activeTableCount.formatted(),
                    label: "Dolu masa"
                )
                OperationWidgetMetric(value: snapshot.waitlistCount, label: "Bekleme", tint: snapshot.waitlistCount > 0 ? OperationWidgetDesign.heroAttention : OperationWidgetDesign.onHero)
                OperationWidgetMetric(value: snapshot.pendingCount, label: "Onay", tint: snapshot.pendingCount > 0 ? OperationWidgetDesign.heroAttention : OperationWidgetDesign.onHero)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OperationWidgetDesign.heroFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(OperationWidgetDesign.contentPadding)
    }
}
