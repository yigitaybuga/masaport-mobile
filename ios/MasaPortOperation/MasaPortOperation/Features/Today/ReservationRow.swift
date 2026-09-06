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

        HStack(alignment: .center, spacing: 12) {
            MPTimeColumn(
                time: reservation.shortTime,
                caption: reservation.guestText,
                tone: {
                    if case .overdue = state { return .critical }
                    if case .now = state { return .info }
                    return nil
                }()
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(reservation.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: reservation.hasTable ? "tablecells" : "tablecells.badge.ellipsis")
                        .font(.caption2)
                    Text(reservation.tableSummary)
                        .lineLimit(1)
                    if let note = reservation.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "text.quote")
                            .font(.caption2)
                            .accessibilityLabel("Not var")
                    }
                }
                .font(.footnote)
                .foregroundStyle(reservation.hasTable ? Color(.secondaryLabel) : MP.attention)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 7) {
                MPStatusLabel(status: status, emphasized: isUrgent)
                if let onCheckIn, reservation.canCheckIn {
                    Button(action: onCheckIn) {
                        HStack(spacing: 5) {
                            if isCheckingIn {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark")
                            }
                            Text("Geldi")
                        }
                    }
                    .buttonStyle(MPCompactButtonStyle(tone: .positive))
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
        case "ARRIVED": "Geldi"
        case "SEATED": "Masada"
        case "BILL": "Hesap"
        case "LEFT": "Ayrıldı"
        case "CLEANING": "Temizlikte"
        case "EMPTY": "Boş"
        default: self
        }
    }
}
