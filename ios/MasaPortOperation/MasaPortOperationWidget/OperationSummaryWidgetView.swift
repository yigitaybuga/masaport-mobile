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
            Color(.systemBackground)
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
                .frame(width: OperationWidgetDesign.markSize, height: OperationWidgetDesign.markSize)
                .accessibilityHidden(true)
            Text(venueName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.reservationCount, format: .number)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("rezervasyon bugün")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: OperationWidgetDesign.sectionSpacing) {
                Label("\(snapshot.waitlistCount)", systemImage: "hourglass")
                    .foregroundStyle(OperationWidgetDesign.attention)
                Label("\(snapshot.overdueCount)", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(snapshot.overdueCount > 0 ? OperationWidgetDesign.critical : .secondary)
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
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
            OperationWidgetHeader(venueName: snapshot.venueName)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: OperationWidgetDesign.sectionSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.reservationCount, format: .number)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("rezervasyon bugün")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if let nextReservation = snapshot.nextReservation {
                        Text("SIRADAKİ")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(OperationWidgetDesign.brand)
                        Text(nextReservation.startTime)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("\(nextReservation.guestCount) kişi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Sırada rezervasyon yok", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack(spacing: OperationWidgetDesign.sectionSpacing) {
                OperationWidgetMetric(value: snapshot.activeTableCount, label: "Aktif masa", systemImage: "tablecells", tint: OperationWidgetDesign.positive)
                OperationWidgetMetric(value: snapshot.waitlistCount, label: "Bekleme", systemImage: "hourglass", tint: OperationWidgetDesign.attention)
                OperationWidgetMetric(value: snapshot.overdueCount, label: "Geciken", systemImage: "clock.badge.exclamationmark", isCritical: snapshot.overdueCount > 0)
                Spacer(minLength: 0)
            }
        }
        .padding(OperationWidgetDesign.contentPadding)
    }
}
