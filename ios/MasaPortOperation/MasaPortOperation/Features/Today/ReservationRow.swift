import SwiftUI

/// Bugün ve Host Masası'nda ortak rezervasyon satırı.
struct ReservationRow: View {
    let reservation: Reservation
    var referenceDate: Date = .now
    var onCheckIn: (() -> Void)? = nil
    var isCheckingIn = false

    var body: some View {
        let state = reservation.operationalState(relativeTo: referenceDate)
        let status = reservation.operationBadge(relativeTo: referenceDate)
        let isUrgent: Bool = {
            switch state {
            case .overdue, .now: true
            default: false
            }
        }()
        let timeTone: MPTone = {
            switch state {
            case .overdue: .critical
            case .now: .info
            case .inside: .positive
            default: .neutral
            }
        }()

        HStack(alignment: .center, spacing: 12) {
            MPTimeBlock(time: reservation.shortTime, caption: reservation.guestText, tone: timeTone)

            VStack(alignment: .leading, spacing: 5) {
                Text(reservation.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if reservation.hasTable {
                        ForEach(reservation.tables.prefix(3)) { table in
                            MPTag(text: table.name, systemImage: "tablecells")
                        }
                        if reservation.tables.count > 3 {
                            Text("+\(reservation.tables.count - 3)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    } else {
                        MPTag(text: "Masa yok", tone: .attention, systemImage: "tablecells.badge.ellipsis")
                    }
                    if reservation.hasNote {
                        Image(systemName: "text.quote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .accessibilityLabel("Not var")
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 8) {
                MPStatusLabel(status: status, emphasized: isUrgent)
                if let onCheckIn, reservation.canCheckIn {
                    Button(action: onCheckIn) {
                        HStack(spacing: 5) {
                            if isCheckingIn {
                                ProgressView().controlSize(.mini).tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                            }
                            Text("Oturdu")
                        }
                    }
                    .buttonStyle(MPCompactButtonStyle(tone: .positive, filled: true))
                    .disabled(isCheckingIn)
                    .accessibilityLabel("\(reservation.displayName) için check-in yap")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(reservation.shortTime), \(reservation.guestText), \(reservation.displayName), \(reservation.tableSummary), \(status.text)"
        )
    }
}

extension String {
    var localizedReservationStatus: String {
        switch uppercased() {
        case "CONFIRMED": "Onaylı"
        case "PENDING": "Bekliyor"
        case "COMPLETED": "Tamamlandı"
        case "CANCELLED": "İptal"
        case "NO_SHOW": "Gelmedi"
        default: self
        }
    }

    var localizedServiceStatus: String {
        switch uppercased() {
        case "ARRIVED", "SEATED", "BILL": "Oturdu"
        case "LEFT", "CLEANING": "Kalktı"
        case "EMPTY": "Boş"
        default: self
        }
    }
}
