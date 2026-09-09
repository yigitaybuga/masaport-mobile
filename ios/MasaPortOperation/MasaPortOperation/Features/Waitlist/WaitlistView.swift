import SwiftUI

struct WaitlistView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = WaitlistViewModel()
    @StateObject private var liveUpdates = HostDeskLiveUpdates()
    @State private var selectedFilter: WaitlistFilter = .all
    @State private var candidate: WaitlistActionCandidate?
    @State private var completionMessage: String?
    @State private var feedbackTrigger = 0
    @State private var convertCandidate: WaitlistEntry?

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
        .sheet(item: $convertCandidate) { entry in
            if let venueID = session.activeVenue?.id {
                WalkInView(venueID: venueID, prefill: entry.walkInPrefill) { _ in
                    Task {
                        if await model.markConverted(entry, venueID: venueID) {
                            completionMessage = "\(entry.customerName) walk-in olarak kaydedildi; bekleme kaydı kapatıldı."
                            feedbackTrigger += 1
                        }
                    }
                }
            }
        }
    }

    private func content(venueID: Int) -> some View {
        List {
            summary
                .mpPlainRow(vertical: 4)

            HStack(spacing: 10) {
                MPSegmentBar(
                    segments: WaitlistFilter.allCases.map { MPSegment(id: $0, title: $0.title, count: $0.count(in: model.entries)) },
                    selection: $selectedFilter
                )
                MPLiveIndicator(isConnected: liveUpdates.state == .connected)
            }
            .mpPlainRow(vertical: 6)

            if let errorMessage = model.errorMessage {
                MPNotice(message: errorMessage, actionTitle: "Yenile") {
                    Task { await model.load(venueID: venueID) }
                }
                .mpPlainRow(vertical: 4)
            }

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
                .mpCard(padding: 0)
                .mpPlainRow(vertical: 4)
            } else {
                Section {
                    ForEach(filteredEntries) { entry in
                        row(entry, venueID: venueID)
                    }
                } header: {
                    MPListSectionHeader(title: selectedFilter.title == "Tümü" ? "Talepler" : selectedFilter.title, count: filteredEntries.count)
                }
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
            MPMetric(value: waitingCount, label: "Bekleyen", tone: waitingCount > 0 ? .attention : .neutral)
            summaryDivider
            MPMetric(value: offeredCount, label: "Teklif gitti", tone: offeredCount > 0 ? .info : .neutral)
            summaryDivider
            MPMetric(value: totalGuests, label: "Toplam kişi", tone: .neutral)
        }
        .mpCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var summaryDivider: some View {
        Rectangle().fill(MP.hairline).frame(width: 1, height: 32).padding(.trailing, 12)
    }

    // MARK: Rows

    private func row(_ entry: WaitlistEntry, venueID: Int) -> some View {
        let isOffered = entry.status == "OFFERED"
        let isBusy = model.actionEntryID == entry.id

        return HStack(alignment: .center, spacing: 12) {
            MPTimeBlock(
                time: entry.shortTime,
                caption: entry.shortDate,
                tone: isOffered ? (entry.offerHasExpired ? .critical : .info) : .neutral
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.customerName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MPTag(text: "\(entry.guestCount) kişi", systemImage: "person.2.fill")
                    Text(entry.waitingText)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
                if let note = entry.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(note, systemImage: "text.quote")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 8) {
                if isOffered {
                    MPStatusLabel(
                        status: MPStatus(
                            text: entry.offerExpiryText ?? "Teklif gitti",
                            tone: entry.offerHasExpired ? .critical : .info
                        ),
                        emphasized: true
                    )
                } else {
                    MPStatusLabel(status: MPStatus(text: "Bekliyor", tone: .attention))
                    Button {
                        candidate = WaitlistActionCandidate(entry: entry, kind: .offer)
                    } label: {
                        HStack(spacing: 5) {
                            if isBusy {
                                ProgressView().controlSize(.mini).tint(MP.onBrand)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Teklif")
                        }
                    }
                    .buttonStyle(MPCompactButtonStyle(tone: .brand, filled: true))
                    .disabled(model.actionEntryID != nil)
                    .accessibilityLabel("\(entry.customerName) için masa teklifi gönder")
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                convertCandidate = entry
            } label: {
                Label("Walk-in", systemImage: "person.badge.plus")
            }
            .tint(MP.positive)
        }
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
            Button("Walk-in'e dönüştür", systemImage: "person.badge.plus") {
                convertCandidate = entry
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
