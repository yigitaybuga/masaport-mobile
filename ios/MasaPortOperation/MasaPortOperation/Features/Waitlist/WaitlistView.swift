import SwiftUI

struct WaitlistView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = WaitlistViewModel()
    @StateObject private var liveUpdates = HostDeskLiveUpdates()
    @State private var selectedFilter: WaitlistFilter = .all
    @State private var candidate: WaitlistActionCandidate?
    @State private var completionMessage: String?
    @State private var feedbackTrigger = 0

    var body: some View {
        Group {
            if let venue = session.activeVenue {
                content(venueID: venue.id)
            } else {
                ContentUnavailableView("Mekan bulunamadı", systemImage: "building.2")
            }
        }
        .background(MP.background)
        .navigationTitle("Bekleme Listesi")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            candidate?.title ?? "",
            isPresented: Binding(
                get: { candidate != nil },
                set: { if !$0 { candidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let candidate {
                Button(candidate.confirmationTitle, role: candidate.kind == .cancel ? .destructive : nil) {
                    perform(candidate)
                }
            }
        } message: {
            Text(candidate?.message ?? "")
        }
        .alert(
            "İşlem tamamlandı",
            isPresented: Binding(
                get: { completionMessage != nil },
                set: { if !$0 { completionMessage = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(completionMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
    }

    private func content(venueID: Int) -> some View {
        List {
            Section {
                summary
                    .mpPlainRow(vertical: 4)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    MPNotice(message: errorMessage, actionTitle: "Yenile") {
                        Task { await model.load(venueID: venueID) }
                    }
                    .mpPlainRow()
                }
            }

            Section {
                if model.isLoading && model.entries.isEmpty {
                    MPLoadingRow(title: "Aktif talepler ve teklifler kontrol ediliyor")
                        .mpPlainRow()
                } else if filteredEntries.isEmpty {
                    MPEmptyState(
                        systemImage: "person.2.badge.checkmark",
                        title: "Aktif bekleme kaydı yok",
                        message: selectedFilter == .all
                            ? "Yeni talepler geldiğinde burada görünecek."
                            : "Bu durumda bekleyen bir misafir bulunmuyor."
                    )
                    .mpPlainRow()
                } else {
                    ForEach(filteredEntries) { entry in
                        row(entry, venueID: venueID)
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    Picker("Filtre", selection: $selectedFilter.animation(.snappy(duration: 0.2))) {
                        ForEach(WaitlistFilter.allCases) { filter in
                            Text("\(filter.title) · \(filter.count(in: model.entries))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    MPLiveIndicator(isConnected: liveUpdates.state == .connected)
                }
                .textCase(nil)
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(venueID: venueID) }
        .task(id: "\(venueID)-\(session.accessToken ?? "")") {
            await model.load(venueID: venueID)
            liveUpdates.onChange = { event in
                guard event.venueID == venueID,
                      event.resources?.contains("waitlist") != false else { return }
                Task { await model.load(venueID: venueID) }
            }
            if let accessToken = session.accessToken {
                liveUpdates.connect(venueID: venueID, accessToken: accessToken)
            }
        }
        .onDisappear { liveUpdates.disconnect() }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 0) {
            summaryMetric(waitingCount, "Bekleyen", tone: .attention)
            summaryDivider
            summaryMetric(offeredCount, "Teklif gitti", tone: .info)
            summaryDivider
            summaryMetric(totalGuests, "Toplam kişi", tone: .neutral)
        }
        .mpCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var summaryDivider: some View {
        Rectangle().fill(MP.separator).frame(width: 1, height: 32)
    }

    private func summaryMetric(_ value: Int, _ title: String, tone: MPTone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? Color(.label) : tone.color)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    // MARK: Rows

    private func row(_ entry: WaitlistEntry, venueID: Int) -> some View {
        let isOffered = entry.status == "OFFERED"
        let isBusy = model.actionEntryID == entry.id

        return HStack(alignment: .center, spacing: 12) {
            MPTimeColumn(
                time: entry.shortTime,
                caption: entry.shortDate,
                tone: isOffered ? .info : nil
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.customerName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(entry.guestCount) kişi · \(entry.waitingText)")
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                if let note = entry.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 7) {
                if isOffered {
                    MPStatusLabel(
                        status: MPStatus(
                            text: entry.offerExpiryText ?? "Teklif gitti",
                            tone: entry.offerHasExpired ? .critical : .info
                        ),
                        emphasized: entry.offerHasExpired
                    )
                } else {
                    MPStatusLabel(status: MPStatus(text: "Bekliyor", tone: .attention))
                    Button {
                        candidate = WaitlistActionCandidate(entry: entry, kind: .offer)
                    } label: {
                        HStack(spacing: 5) {
                            if isBusy {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Teklif")
                        }
                    }
                    .buttonStyle(MPCompactButtonStyle(tone: .brand))
                    .disabled(model.actionEntryID != nil)
                    .accessibilityLabel("\(entry.customerName) için masa teklifi gönder")
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                candidate = WaitlistActionCandidate(entry: entry, kind: .cancel)
            } label: {
                Label("Kaldır", systemImage: "xmark")
            }
            if let phoneURL = entry.phoneURL {
                Link(destination: phoneURL) {
                    Label("Ara", systemImage: "phone.fill")
                }
                .tint(MP.info)
            }
        }
        .contextMenu {
            if entry.status == "WAITING" {
                Button("Teklif gönder", systemImage: "paperplane") {
                    candidate = WaitlistActionCandidate(entry: entry, kind: .offer)
                }
            }
            if let phoneURL = entry.phoneURL {
                Link(destination: phoneURL) {
                    Label("Ara \(entry.customerPhone)", systemImage: "phone")
                }
            }
            Button("Listeden kaldır", systemImage: "xmark.circle", role: .destructive) {
                candidate = WaitlistActionCandidate(entry: entry, kind: .cancel)
            }
        }
    }

    // MARK: Actions

    private func perform(_ candidate: WaitlistActionCandidate) {
        self.candidate = nil
        guard let venueID = session.activeVenue?.id else { return }
        Task {
            let succeeded: Bool
            switch candidate.kind {
            case .offer:
                succeeded = await model.sendOffer(for: candidate.entry, venueID: venueID)
                if succeeded { completionMessage = "Masa teklifi misafire gönderildi." }
            case .cancel:
                succeeded = await model.cancel(candidate.entry, venueID: venueID)
                if succeeded { completionMessage = "Misafir bekleme listesinden kaldırıldı." }
            }
            if succeeded { feedbackTrigger += 1 }
        }
    }

    private var filteredEntries: [WaitlistEntry] {
        switch selectedFilter {
        case .all: model.entries
        case .waiting: model.entries.filter { $0.status == "WAITING" }
        case .offered: model.entries.filter { $0.status == "OFFERED" }
        }
    }

    private var waitingCount: Int { model.entries.count { $0.status == "WAITING" } }
    private var offeredCount: Int { model.entries.count { $0.status == "OFFERED" } }
    private var totalGuests: Int { model.entries.reduce(0) { $0 + $1.guestCount } }
}
