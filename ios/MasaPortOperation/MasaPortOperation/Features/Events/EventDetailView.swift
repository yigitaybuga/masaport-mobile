import SwiftUI

struct EventDetailView: View {
    let event: EventSummary
    let venueID: Int

    @StateObject private var model = EventDetailViewModel()
    @State private var selectedInstanceID: Int?
    @State private var searchText = ""
    @State private var filter: GuestFilter = .all
    @State private var checkInCandidate: EventReservation?
    @State private var noteCandidate: EventReservation?
    @StateObject private var searchHistory = SearchHistoryStore(scope: "event-guests")
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
                    .mpCard(padding: 0)
                    .mpPlainRow(vertical: 4)
                } else {
                    ForEach(filteredReservations) { reservation in
                        EventReservationRow(
                            reservation: reservation,
                            isCheckingIn: model.checkingInID == reservation.id,
                            onCheckIn: { checkInCandidate = reservation },
                            onEditNote: { noteCandidate = reservation }
                        )
                    }
                }
            } header: {
                MPSegmentBar(
                    segments: GuestFilter.allCases.map { MPSegment(id: $0, title: $0.title, count: $0.count(in: instanceReservations)) },
                    selection: $filter
                )
                .textCase(nil)
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MP.background)
        .searchable(text: $searchText, prompt: "Katılımcı, telefon veya misafir")
        .searchSuggestions {
            HostDeskSearchSuggestions(
                query: searchText,
                history: searchHistory,
                candidates: model.reservations.flatMap { [$0.contactName] + ($0.eventGuests ?? []).map(\.fullName) }
            )
        }
        .onSubmit(of: .search) { searchHistory.record(searchText) }
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
        .sheet(item: $noteCandidate) { reservation in
            EventGuestNoteSheet(reservation: reservation) { note in
                await model.updateNote(reservation, note: note, venueID: venueID, eventID: event.id)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                MPDateLeaf(
                    day: EventDates.dayNumber(selectedInstance?.startDatetime ?? event.startDatetime),
                    month: EventDates.monthShort(selectedInstance?.startDatetime ?? event.startDatetime),
                    tone: event.activeInstance != nil && event.activeInstance?.id == selectedInstanceID ? .positive : .brand
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
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
                            .foregroundStyle(MP.brand)
                        Text(selectedInstance.map { "\($0.dayText) · \($0.timeRangeText)" } ?? "Seans seç")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(MP.fill, in: Capsule())
                    .overlay { Capsule().strokeBorder(MP.hairline, lineWidth: 1) }
                }
            } else if let instance = selectedInstance {
                Label("\(instance.dayText) · \(instance.timeRangeText)", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            HStack(spacing: 14) {
                ZStack {
                    MPProgressRing(progress: Double(checkedInGuests) / Double(max(1, totalGuests)), lineWidth: 6, tone: .positive)
                    VStack(spacing: -1) {
                        Text(checkedInGuests, format: .number)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("/ \(totalGuests)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .frame(width: 58, height: 58)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("İçeride \(checkedInGuests) / \(totalGuests) kişi")

                HStack(spacing: 0) {
                    MPMetric(value: checkedInGuests, label: "İçeride", tone: .positive)
                    MPMetric(value: paidGuests, label: "Bekleniyor", tone: paidGuests > 0 ? .info : .neutral)
                    MPMetric(value: capacityValue, label: "Kapasite", tone: .neutral)
                }
            }
        }
        .mpCard()
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
    let onEditNote: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                MPAvatar(name: reservation.displayName, size: 42, tone: reservation.isCheckedIn ? .positive : .brand)

                VStack(alignment: .leading, spacing: 5) {
                    Text(reservation.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        MPTag(text: "\(reservation.guestCount) kişi", tone: reservation.isCheckedIn ? .positive : .neutral, systemImage: "person.2.fill")
                            .fixedSize()
                        if let phone = reservation.contactPhone, !phone.isEmpty {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
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

                VStack(alignment: .trailing, spacing: 7) {
                    MPStatusLabel(status: status, emphasized: reservation.isCheckedIn)
                    if !reservation.isCheckedIn && reservation.isPaid {
                        Button(action: onCheckIn) {
                            HStack(spacing: 5) {
                                if isCheckingIn { ProgressView().controlSize(.mini).tint(.white) } else { Image(systemName: "checkmark") }
                                Text("Geldi")
                            }
                        }
                        .buttonStyle(MPCompactButtonStyle(tone: .positive, filled: true))
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
                .padding(.leading, 54)
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
            Button(reservation.hasNote ? "Notu düzenle" : "Not ekle", systemImage: "text.quote", action: onEditNote)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onEditNote) { Label("Not", systemImage: "text.quote") }
                .tint(MP.attention)
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

extension EventReservation {
    var hasNote: Bool { !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Etkinlik katılımcısı notu düzenleme.
private struct EventGuestNoteSheet: View {
    let reservation: EventReservation
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(reservation: EventReservation, onSave: @escaping (String) async -> Bool) {
        self.reservation = reservation
        self.onSave = onSave
        _note = State(initialValue: reservation.note ?? "")
    }

    private var hasChanges: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines) != (reservation.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MPAvatar(name: reservation.displayName, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reservation.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(reservation.guestCount) kişi")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    Spacer(minLength: 0)
                }
                .mpCard(padding: 12)

                TextField("Alerji, masa tercihi, kutlama…", text: $note, axis: .vertical)
                    .lineLimit(4...8)
                    .focused($isFocused)
                    .mpCard(padding: 14)

                Text("Not yalnızca operasyon ekibine görünür; misafire gönderilmez.")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))

                if let errorMessage {
                    MPNotice(message: errorMessage)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 8)
            .background(MP.background)
            .navigationTitle(reservation.hasNote ? "Notu düzenle" : "Not ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isFocused = false
                    Task {
                        isSubmitting = true
                        errorMessage = nil
                        let ok = await onSave(note.trimmingCharacters(in: .whitespacesAndNewlines))
                        isSubmitting = false
                        if ok { dismiss() } else { errorMessage = "Not kaydedilemedi. Katılımcı listesindeki uyarıyı kontrol edin." }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(MP.onBrand) }
                        Text(isSubmitting ? "Kaydediliyor…" : (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reservation.hasNote ? "Notu sil" : "Notu kaydet"))
                    }
                }
                .buttonStyle(MPPrimaryButtonStyle())
                .disabled(!hasChanges || isSubmitting)
                .opacity(hasChanges ? 1 : 0.5)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
