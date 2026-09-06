import SwiftUI

struct EventDetailView: View {
    let event: EventSummary
    let venueID: Int

    @StateObject private var model = EventDetailViewModel()
    @State private var selectedInstanceID: Int?
    @State private var searchText = ""
    @State private var filter: GuestFilter = .all
    @State private var checkInCandidate: EventReservation?
    @State private var showsScanner = false

    var body: some View {
        List {
            Section {
                header
                    .mpPlainRow(vertical: 4)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    MPNotice(message: errorMessage, actionTitle: "Yenile") {
                        Task { await model.load(venueID: venueID, eventID: event.id) }
                    }
                    .mpPlainRow()
                }
            }

            Section {
                if model.isLoading && model.reservations.isEmpty {
                    MPLoadingRow(title: "Katılımcılar yükleniyor")
                        .mpPlainRow()
                } else if filteredReservations.isEmpty {
                    MPEmptyState(
                        systemImage: searchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                        title: searchText.isEmpty ? "Bu seansta katılımcı yok" : "Eşleşen katılımcı bulunamadı",
                        message: searchText.isEmpty ? "Rezervasyon geldikçe burada listelenir." : "Ad, telefon veya misafir adıyla arayın."
                    )
                    .mpPlainRow()
                } else {
                    ForEach(filteredReservations) { reservation in
                        EventReservationRow(
                            reservation: reservation,
                            isCheckingIn: model.checkingInID == reservation.id,
                            onCheckIn: { checkInCandidate = reservation }
                        )
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    Picker("Filtre", selection: $filter.animation(.snappy(duration: 0.2))) {
                        ForEach(GuestFilter.allCases) { item in
                            Text("\(item.title) · \(item.count(in: instanceReservations))").tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .textCase(nil)
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MP.background)
        .searchable(text: $searchText, prompt: "Katılımcı, telefon veya misafir")
        .navigationTitle("Katılımcılar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QRScanButton(isPresented: $showsScanner)
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            CheckinScannerView {
                Task { await model.load(venueID: venueID, eventID: event.id) }
            }
        }
        .refreshable { await model.load(venueID: venueID, eventID: event.id) }
        .task {
            if selectedInstanceID == nil { selectedInstanceID = event.displayedInstance?.id }
            await model.load(venueID: venueID, eventID: event.id)
        }
        .confirmationDialog(
            "Katılımcı geldi mi?",
            isPresented: Binding(get: { checkInCandidate != nil }, set: { if !$0 { checkInCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Check-in yap") {
                guard let reservation = checkInCandidate else { return }
                checkInCandidate = nil
                Task { _ = await model.checkIn(reservation, venueID: venueID, eventID: event.id) }
            }
        } message: {
            Text("\(checkInCandidate?.displayName ?? "Katılımcı") için \(checkInCandidate?.guestCount ?? 0) kişilik giriş kaydı oluşturulacak.")
        }
        .sensoryFeedback(.success, trigger: model.successCount)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(.label))
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }

            if instances.count > 1 {
                Menu {
                    ForEach(instances) { instance in
                        Button {
                            selectedInstanceID = instance.id
                        } label: {
                            if instance.id == selectedInstanceID {
                                Label("\(instance.dayText) · \(instance.timeRangeText)", systemImage: "checkmark")
                            } else {
                                Text("\(instance.dayText) · \(instance.timeRangeText)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(selectedInstance.map { "\($0.dayText) · \($0.timeRangeText)" } ?? "Seans seç")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(MP.fill, in: Capsule())
                }
            } else if let instance = selectedInstance {
                Label("\(instance.dayText) · \(instance.timeRangeText)", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
            }

            HStack(spacing: 0) {
                headerFact(value: "\(checkedInGuests)", label: "içeride", tone: .positive)
                headerFact(value: "\(paidGuests)", label: "bekleniyor", tone: .info)
                headerFact(value: capacityValue, label: "kapasite", tone: nil)
            }

            ProgressView(value: Double(checkedInGuests), total: Double(max(1, totalGuests)))
                .tint(MP.positive)
        }
        .mpCard()
    }

    private func headerFact(value: String, label: String, tone: MPTone?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone?.color ?? Color(.label))
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Data

    private var instances: [EventInstanceSummary] { event.allInstances }
    private var selectedInstance: EventInstanceSummary? { instances.first { $0.id == selectedInstanceID } }

    private var instanceReservations: [EventReservation] {
        guard let selectedInstanceID else { return model.reservations }
        return model.reservations.filter { $0.eventInstanceId == selectedInstanceID || $0.eventInstance?.id == selectedInstanceID }
    }

    private var filteredReservations: [EventReservation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return instanceReservations
            .filter { filter.matches($0) }
            .filter { reservation in
                guard !query.isEmpty else { return true }
                var haystack = [reservation.contactName, reservation.contactPhone ?? "", reservation.uuid ?? ""]
                haystack.append(contentsOf: (reservation.eventGuests ?? []).map(\.fullName))
                return haystack.contains { $0.lowercased().contains(query) }
            }
            .sorted { lhs, rhs in
                if lhs.isCheckedIn != rhs.isCheckedIn { return !lhs.isCheckedIn }
                return lhs.contactName.localizedCaseInsensitiveCompare(rhs.contactName) == .orderedAscending
            }
    }

    private var totalGuests: Int { instanceReservations.filter(\.isPaid).reduce(0) { $0 + $1.guestCount } }
    private var checkedInGuests: Int { instanceReservations.filter(\.isCheckedIn).reduce(0) { $0 + $1.guestCount } }
    private var paidGuests: Int { instanceReservations.filter { $0.isPaid && !$0.isCheckedIn }.reduce(0) { $0 + $1.guestCount } }
    private var capacityValue: String {
        if let capacity = event.maxCapacity, capacity > 0 { return "\(selectedInstance?.soldTickets ?? totalGuests) / \(capacity)" }
        return "\(selectedInstance?.soldTickets ?? totalGuests)"
    }
}

private enum GuestFilter: String, CaseIterable, Identifiable {
    case all, waiting, inside

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .waiting: "Bekleniyor"
        case .inside: "İçeride"
        }
    }

    func matches(_ reservation: EventReservation) -> Bool {
        switch self {
        case .all: true
        case .waiting: !reservation.isCheckedIn
        case .inside: reservation.isCheckedIn
        }
    }

    func count(in reservations: [EventReservation]) -> Int {
        reservations.count(where: matches)
    }
}

private struct EventReservationRow: View {
    let reservation: EventReservation
    let isCheckingIn: Bool
    let onCheckIn: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(reservation.guestCount, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(reservation.isCheckedIn ? MP.positive : Color(.label))
                    .frame(width: 40, height: 40)
                    .background((reservation.isCheckedIn ? MP.positive : MP.brand).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("\(reservation.guestCount) kişi")

                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let phone = reservation.contactPhone, !phone.isEmpty {
                            Text(phone)
                        }
                        if let guests = reservation.eventGuests, guests.count > 1 {
                            Text("·")
                            Text("\(guests.count) misafir")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 7) {
                    MPStatusLabel(status: status, emphasized: reservation.isCheckedIn)
                    if !reservation.isCheckedIn && reservation.isPaid {
                        Button(action: onCheckIn) {
                            HStack(spacing: 5) {
                                if isCheckingIn { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark") }
                                Text("Geldi")
                            }
                        }
                        .buttonStyle(MPCompactButtonStyle(tone: .positive))
                        .disabled(isCheckingIn)
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let guests = reservation.eventGuests, !guests.isEmpty {
                        ForEach(guests) { guest in
                            Label(guest.fullName, systemImage: "person")
                                .font(.footnote)
                                .foregroundStyle(Color(.label))
                        }
                    }
                    if let note = reservation.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(note, systemImage: "text.quote")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    if let amount = reservation.totalAmount?.value {
                        Label(amount.formatted(.currency(code: "TRY").locale(Locale(identifier: "tr_TR"))), systemImage: "creditcard")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    if let code = reservation.uuid {
                        Label(String(code.suffix(8)).uppercased(), systemImage: "number")
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(.leading, 52)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
        }
        .contextMenu {
            if let phone = reservation.contactPhone,
               let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) { Label("Ara \(phone)", systemImage: "phone") }
            }
            if !reservation.isCheckedIn && reservation.isPaid {
                Button("Check-in yap", systemImage: "person.fill.checkmark", action: onCheckIn)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !reservation.isCheckedIn && reservation.isPaid {
                Button(action: onCheckIn) { Label("Geldi", systemImage: "person.fill.checkmark") }
                    .tint(MP.positive)
            }
        }
    }

    private var status: MPStatus {
        if reservation.isCheckedIn {
            let at = reservation.checkedInAt.map { EventDates.time($0) } ?? ""
            return MPStatus(text: at.isEmpty ? "İçeride" : "İçeride · \(at)", tone: .positive)
        }
        switch (reservation.paymentStatus ?? "").uppercased() {
        case "PAID": return MPStatus(text: "Ödendi", tone: .info)
        case "PENDING": return MPStatus(text: "Ödeme bekliyor", tone: .attention)
        case "REFUNDED": return MPStatus(text: "İade edildi", tone: .critical)
        case "FAILED": return MPStatus(text: "Ödeme başarısız", tone: .critical)
        default: return MPStatus(text: reservation.paymentStatus ?? "—", tone: .neutral)
        }
    }
}
