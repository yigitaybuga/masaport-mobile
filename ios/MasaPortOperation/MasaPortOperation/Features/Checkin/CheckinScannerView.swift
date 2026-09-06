import SwiftUI
import UIKit

@MainActor
final class CheckinScannerViewModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case resolving
        case resolved(CheckinStatus)
        case checkingIn(CheckinStatus)
        case success(CheckinResult)
        case failure(String)
    }

    @Published private(set) var phase: Phase = .scanning
    @Published var manualCode = ""
    @Published private(set) var successCount = 0

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func handle(rawCode: String) {
        guard isScanning else { return }
        guard let identifier = CheckinIdentifier.normalize(rawCode) else {
            phase = .failure("Geçersiz kod. Geçerli bir rezervasyon QR'ı okutun veya 8 haneli kısa kodu girin.")
            return
        }
        Task { await resolve(identifier) }
    }

    func submitManualCode() {
        let code = manualCode
        manualCode = ""
        handle(rawCode: code)
    }

    func reset() {
        phase = .scanning
    }

    private func resolve(_ identifier: String) async {
        phase = .resolving
        do {
            let payload: CheckinPayload<CheckinStatus> = try await api.get("/checkin/status/\(identifier)")
            guard payload.success, let status = payload.data else {
                phase = .failure(payload.error ?? payload.message ?? "Rezervasyon bulunamadı.")
                return
            }
            phase = .resolved(status)
        } catch let error as APIError {
            phase = .failure(error.statusCode == 404 ? "Bu koda ait rezervasyon bulunamadı." : (error.detail ?? error.message))
        } catch {
            phase = .failure("Rezervasyon sorgulanamadı. Bağlantınızı kontrol edin.")
        }
    }

    func checkIn(_ status: CheckinStatus, force: Bool = false) async {
        phase = .checkingIn(status)
        do {
            let payload: CheckinPayload<CheckinResult>
            if status.isEvent {
                payload = try await api.post("/checkin/event/\(status.uuid)")
            } else {
                payload = try await api.post(
                    "/checkin/restaurant/\(status.uuid)",
                    body: RestaurantCheckinRequest(forceCheckIn: force ? true : nil, expectedUpdatedAt: nil)
                )
            }
            guard payload.success, let result = payload.data else {
                phase = .failure(payload.error ?? payload.message ?? "Check-in tamamlanamadı.")
                return
            }
            successCount += 1
            phase = .success(result)
        } catch let error as APIError {
            if error.isEarlyCheckInWarning {
                phase = .resolved(status)
                return
            }
            phase = .failure(error.detail ?? error.message)
        } catch {
            phase = .failure("Check-in tamamlanamadı. Tekrar deneyin.")
        }
    }
}

/// Tam ekran QR tarayıcı; restoran ve etkinlik rezervasyonlarını tek akışta karşılar.
struct CheckinScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CheckinScannerViewModel()
    @State private var cameraAllowed: Bool?
    @State private var showsEarlyConfirmation = false
    @FocusState private var manualFieldFocused: Bool

    var onCheckedIn: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            scrim

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .preferredColorScheme(.dark)
        .task {
            cameraAllowed = CameraAccess.hasCamera ? await CameraAccess.request() : false
        }
        .sensoryFeedback(.success, trigger: model.successCount)
        .confirmationDialog(
            "Erken check-in",
            isPresented: $showsEarlyConfirmation,
            titleVisibility: .visible
        ) {
            if case .resolved(let status) = model.phase {
                Button("Yine de check-in yap") {
                    Task { await model.checkIn(status, force: true) }
                }
            }
        } message: {
            if case .resolved(let status) = model.phase {
                Text(status.checkInWarning ?? "Rezervasyon saati henüz gelmedi.")
            }
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var cameraLayer: some View {
        if cameraAllowed == true {
            QRCameraView(isActive: model.isScanning) { code in
                model.handle(rawCode: code)
            }
            .ignoresSafeArea()
        } else {
            VStack(spacing: 10) {
                Image(systemName: cameraAllowed == false ? "camera.slash" : "camera")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(cameraAllowed == false ? (CameraAccess.hasCamera ? "Kamera izni verilmedi" : "Bu cihazda kamera yok") : "Kamera hazırlanıyor")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if cameraAllowed == false, CameraAccess.hasCamera,
                   let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Ayarlar'da izin ver", destination: settings)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MP.brand)
                }
                Text("Kısa kodu aşağıdan elle girebilirsiniz.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: 40)
        }
    }

    private var scrim: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.62
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: proxy.size.height * 0.36 - side / 2,
                width: side,
                height: side
            )
            ZStack {
                Color.black.opacity(model.isScanning && cameraAllowed == true ? 0.45 : 0.7)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                ScannerCorners()
                    .stroke(model.isScanning ? Color.white : MP.positive, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(.easeOut(duration: 0.2), value: model.isScanning)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .accessibilityLabel("Tarayıcıyı kapat")
            Spacer()
            VStack(spacing: 2) {
                Text("QR Check-in")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Rezervasyon QR'ını çerçeveye getirin")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, MP.gutter)
        .padding(.top, 8)
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .scanning:
                manualEntry
            case .resolving:
                statusCard {
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Rezervasyon sorgulanıyor…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            case .resolved(let status):
                resolvedCard(status, isBusy: false)
            case .checkingIn(let status):
                resolvedCard(status, isBusy: true)
            case .success(let result):
                successCard(result)
            case .failure(let message):
                failureCard(message)
            }
        }
        .padding(.horizontal, MP.gutter)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.28), value: model.phase)
    }

    private var manualEntry: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.white.opacity(0.7))
                TextField("", text: $model.manualCode, prompt: Text(manualPrompt).foregroundStyle(.white.opacity(0.45)))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.search)
                    .focused($manualFieldFocused)
                    .onSubmit { model.submitManualCode() }
                Button {
                    model.submitManualCode()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(model.manualCode.isEmpty ? .white.opacity(0.3) : .white)
                }
                .disabled(model.manualCode.isEmpty)
                .accessibilityLabel("Kodu sorgula")
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("QR okunamıyorsa misafirin 8 haneli kısa kodunu girin.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var manualPrompt: String {
        #if DEBUG
        if DemoMode.isEnabled { return "Kısa kod · örnek: \(DemoStore.shared.sampleShortCode)" }
        #endif
        return "Kısa kod veya rezervasyon kodu"
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func resolvedCard(_ status: CheckinStatus, isBusy: Bool) -> some View {
        let state = resolvedState(status)
        return statusCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: status.isEvent ? "ticket.fill" : "fork.knife")
                        .font(.headline)
                        .foregroundStyle(MP.onBrand)
                        .frame(width: 38, height: 38)
                        .background(MP.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.displayName)
                            .font(.title3.weight(.bold))
                        Text(subtitle(for: status))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    MPPill(text: state.pill.text, tone: state.pill.tone)
                }

                if let note = state.note {
                    Label(note, systemImage: state.noteSymbol)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Yeni tarama") { model.reset() }
                        .buttonStyle(ScannerSecondaryButtonStyle())
                        .disabled(isBusy)

                    if state.canCheckIn {
                        Button {
                            if status.needsEarlyConfirmation {
                                showsEarlyConfirmation = true
                            } else {
                                Task { await model.checkIn(status) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isBusy { ProgressView().tint(.white) }
                                Text(status.needsEarlyConfirmation ? "Erken check-in" : "Check-in yap")
                            }
                        }
                        .buttonStyle(MPPrimaryButtonStyle(tone: status.needsEarlyConfirmation ? .attention : .positive))
                        .disabled(isBusy)
                    }
                }
            }
        }
    }

    private func successCard(_ result: CheckinResult) -> some View {
        statusCard {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(MP.positive)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.displayName) karşılandı")
                            .font(.headline)
                        Text(successDetail(result))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                Button("Sonraki misafir") {
                    onCheckedIn?()
                    model.reset()
                }
                .buttonStyle(MPPrimaryButtonStyle(tone: .positive))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            if case .success = model.phase {
                onCheckedIn?()
                model.reset()
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        statusCard {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(MP.attention)
                    Text(message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button("Tekrar dene") { model.reset() }
                    .buttonStyle(ScannerSecondaryButtonStyle())
            }
        }
    }

    // MARK: Presentation helpers

    private struct ResolvedState {
        let pill: MPStatus
        let note: String?
        let noteSymbol: String
        let canCheckIn: Bool
    }

    private func resolvedState(_ status: CheckinStatus) -> ResolvedState {
        if status.isCheckedIn {
            let at = status.checkedInAt.map { EventDates.time($0) } ?? ""
            return ResolvedState(
                pill: MPStatus(text: "Zaten içeride", tone: .positive),
                note: at.isEmpty ? "Bu rezervasyon daha önce check-in yapılmış." : "Check-in \(at) saatinde yapılmış.",
                noteSymbol: "checkmark.circle", canCheckIn: false
            )
        }
        if status.isEvent, !status.isPaid {
            return ResolvedState(
                pill: MPStatus(text: "Ödeme bekliyor", tone: .attention),
                note: "Yalnızca ödemesi tamamlanmış etkinlik rezervasyonları check-in yapılabilir.",
                noteSymbol: "creditcard", canCheckIn: false
            )
        }
        if !status.isEvent, let reservationStatus = status.status?.uppercased(), reservationStatus != "CONFIRMED" {
            return ResolvedState(
                pill: MPStatus(text: reservationStatus.localizedReservationStatus, tone: .critical),
                note: "Yalnızca onaylı rezervasyonlar check-in yapılabilir.",
                noteSymbol: "xmark.circle", canCheckIn: false
            )
        }
        if status.needsEarlyConfirmation {
            return ResolvedState(
                pill: MPStatus(text: "Erken geldi", tone: .attention),
                note: status.checkInWarning, noteSymbol: "clock", canCheckIn: true
            )
        }
        return ResolvedState(pill: MPStatus(text: "Hazır", tone: .info), note: nil, noteSymbol: "", canCheckIn: true)
    }

    private func subtitle(for status: CheckinStatus) -> String {
        var parts: [String] = ["\(status.guestCount) kişi"]
        if status.isEvent {
            if let title = status.eventTitle { parts.append(title) }
            if let start = status.eventStartTime { parts.append(EventDates.time(start)) }
        } else {
            if let startTime = status.startTime { parts.append(String(startTime.prefix(5))) }
            if let tables = status.tables, !tables.isEmpty { parts.append(tables.joined(separator: ", ")) }
        }
        return parts.joined(separator: " · ")
    }

    private func successDetail(_ result: CheckinResult) -> String {
        var parts: [String] = ["\(result.guestCount) kişi"]
        if let title = result.eventTitle { parts.append(title) }
        if let tables = result.tables, !tables.isEmpty { parts.append(tables.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

private struct ScannerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white.opacity(configuration.isPressed ? 0.1 : 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        let radius: CGFloat = 22
        var path = Path()
        // Sol üst
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Sağ üst
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Sağ alt
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Sol alt
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .center) {
                    mask().blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

/// Araç çubuğu QR düğmesi.
struct QRScanButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel("QR ile check-in")
    }
}
