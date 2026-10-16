import AppKit
import SwiftUI
import PaCoShared

struct ChildModeView: View {
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @EnvironmentObject private var bonjour: BonjourService
    @Environment(AppState.self) private var appState
    @ObservedObject private var requestLog = ChildRequestLog.shared
    @State private var showPINPrompt = false
    @State private var requestError = ""
    @State private var pinEntry = ""
    @State private var pinError = ""
    @State private var pinBusy = false
    @State private var showRequestOverlay = false
    @State private var requestMinutes = 30
    @State private var requestReason = ""
    @State private var showPairingPrompt = false
    @State private var pairingCode = ""
    @State private var pairingError = ""
    @State private var todayUsage: UsageTransfer?
    @State private var usageRefreshTimer: Timer?
    @State private var cloudRefreshTimer: Timer?
    @State private var showCloudEnroll = false
    @State private var showCloudInfo = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                // Status icon
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(daemonClient.isInternetEnabled ? .green : .red)
                    .animation(.easeInOut, value: daemonClient.isInternetEnabled)

                // Status text
                Text(daemonClient.isInternetEnabled ? "Internet is ON" : "Internet is OFF")
                    .font(.title)
                    .fontWeight(.semibold)

                // Parent link status
                HStack(spacing: 6) {
                    Circle()
                        .fill(isParentReachable ? .green : (isLinked ? .orange : .secondary))
                        .frame(width: 8, height: 8)
                    Text(parentStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.horizontal, 40)

                // Today's usage
                VStack(spacing: 8) {
                    Text("Today's Usage")
                        .font(.headline)
                    if let usage = todayUsage {
                        Text("Internet: \(formatDuration(usage.internetOnDuration))")
                            .font(.subheadline)
                        ForEach(topApps(usage), id: \.bundleIdentifier) { app in
                            Text("\(app.appName): \(formatDuration(app.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No usage recorded yet today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                requestStatusView

                if pendingRequest == nil {
                    Button("Request More Time") {
                        requestError = ""
                        showRequestOverlay = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isParentReachable)
                    .padding(.top, 4)
                }
                if !requestError.isEmpty {
                    Text(requestError).font(.caption).foregroundStyle(.red)
                }

                Spacer()

                // Footer: pairing + parent access.
                // Note: no Quit button in child mode — the monitored user should
                // not be able to stop PaCo from the UI.
                HStack {
                    if isCloud {
                        Button(cloudFooterTitle) { showCloudInfo = true }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Pair with Parent") {
                            pairingCode = ""
                            pairingError = ""
                            showPairingPrompt = true
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !isPaired {
                            Button("Use PaCo Cloud") { showCloudEnroll = true }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Parent Access") {
                        pinError = isParentReachable ? "" : unreachableMessage
                        showPINPrompt = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(30)
            .frame(width: 350, height: 460)
            .onAppear {
                loadUsage()
                daemonClient.refreshStatus()
                usageRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                    loadUsage()
                    daemonClient.refreshStatus()
                }
                // A cloud approval lands in the daemon within a second; show it promptly.
                cloudRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                    if isCloud { daemonClient.refreshCloudStatus() }
                }
            }
            .onDisappear {
                usageRefreshTimer?.invalidate()
                usageRefreshTimer = nil
                cloudRefreshTimer?.invalidate()
                cloudRefreshTimer = nil
            }

            if showRequestOverlay {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Request More Time").font(.headline)
                    Stepper("\(requestMinutes) minutes", value: $requestMinutes, in: 15...120, step: 15)
                        .frame(width: 200)
                    TextField("Reason (optional)", text: $requestReason)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    HStack {
                        Button("Cancel") {
                            showRequestOverlay = false
                            requestReason = ""
                        }
                        Button("Send Request") {
                            sendExtensionRequest()
                            showRequestOverlay = false
                            requestReason = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }

            if showPairingPrompt {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Pair with Parent").font(.headline)
                    Text("Enter the pairing code shown on the parent's Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    TextField("Pairing code", text: $pairingCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .autocorrectionDisabled()
                    if !pairingError.isEmpty {
                        Text(pairingError).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        Button("Cancel") {
                            showPairingPrompt = false
                            pairingCode = ""
                            pairingError = ""
                        }
                        Button("Pair") { completePairing() }
                            .buttonStyle(.borderedProminent)
                            .disabled(pairingCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(30)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }

            if showCloudEnroll {
                Color.black.opacity(0.3).ignoresSafeArea()
                CloudEnrollView(
                    onCancel: { showCloudEnroll = false },
                    onEnrolled: {
                        showCloudEnroll = false
                        appState.setController(.cloud, context: modelContext)
                    })
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
            }

            if showCloudInfo {
                Color.black.opacity(0.3).ignoresSafeArea()
                cloudInfoView
                    .padding(30)
                    .frame(width: 320)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
            }

            if showPINPrompt {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Enter Parent PIN").font(.headline)
                    Text(isCloud
                         ? "Checked with PaCo Cloud — nothing PIN-related is stored here."
                         : "Checked with the parent's Mac — nothing PIN-related is stored here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    SecureField("PIN", text: $pinEntry)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit { verifyPIN() }
                        .disabled(pinBusy)
                    if !pinError.isEmpty {
                        Text(pinError).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        Button("Cancel") {
                            showPINPrompt = false
                            pinEntry = ""
                            pinError = ""
                        }
                        Button(pinBusy ? "Checking…" : "Unlock") {
                            verifyPIN()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pinBusy || pinEntry.isEmpty)
                    }
                }
                .padding(30)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }

    // MARK: - Status helpers

    private var isPaired: Bool { PairingKeyManager.hasAnyKey() }

    /// Managed by PaCo Cloud rather than a parent Mac nearby.
    private var isCloud: Bool { appState.controller == .cloud }

    private var cloud: CloudStatus? { daemonClient.cloudStatus }

    /// Paired (Bonjour) or enrolled (cloud), whether or not reachable right now.
    private var isLinked: Bool { isCloud ? (cloud?.enrolled ?? true) : isPaired }

    /// Whether the parent can be asked right now (requests, PIN checks).
    private var isParentReachable: Bool {
        isCloud ? (cloud?.enrolled == true && cloud?.connected == true) : bonjour.isParentConnected
    }

    private var unreachableMessage: String {
        isCloud ? "PaCo Cloud must be reachable to check the PIN." : "The parent's Mac must be connected to check the PIN."
    }

    private var parentStatusText: String {
        if isCloud {
            guard let cloud else { return "PaCo Cloud" }
            if !cloud.enrolled { return "Disconnected from PaCo Cloud" }
            return cloud.connected ? "Connected to PaCo Cloud" : "PaCo Cloud not reachable"
        }
        if bonjour.isParentConnected { return "Connected to parent" }
        return isPaired ? "Paired — parent not connected" : "Not paired with a parent"
    }

    private var cloudFooterTitle: String {
        cloud?.enrolled == false ? "Reconnect to PaCo Cloud" : "PaCo Cloud"
    }

    /// The child's requests: kept by the daemon in cloud mode, by the app otherwise.
    private var pendingRequest: ChildRequestRecord? {
        isCloud ? cloud?.pendingRequest : requestLog.pending
    }

    private var latestRequest: ChildRequestRecord? {
        isCloud ? cloud?.latestRequest : requestLog.latest
    }

    private func withdrawRequest() {
        guard isCloud else {
            requestLog.withdrawPending()
            return
        }
        guard let id = pendingRequest?.id else { return }
        daemonClient.cloud(.withdrawRequest(requestId: id)) { response in
            if !response.ok { requestError = response.error ?? "Could not withdraw the request." }
        }
    }

    /// Details of the PaCo Cloud link. Disconnecting needs the parent: it lives
    /// in Settings behind Parent Access.
    @ViewBuilder
    private var cloudInfoView: some View {
        VStack(spacing: 12) {
            Text("PaCo Cloud").font(.headline)
            if let cloud, cloud.enrolled {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Server", value: cloud.serverURL?.host ?? "—")
                    LabeledContent("This Mac", value: cloud.deviceName ?? "—")
                    LabeledContent("Last contact", value: cloud.lastContactAt?.formatted(date: .omitted, time: .standard) ?? "never")
                }
                .font(.caption)
                if let error = cloud.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
                Text("Screen time and requests go to the parent's PaCo Cloud page.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Close") { showCloudInfo = false }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(cloud?.lastError ?? "This Mac is not connected to PaCo Cloud. The last rules the parent set still apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Close") { showCloudInfo = false }
                    Button("Connect…") {
                        showCloudInfo = false
                        showCloudEnroll = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    /// Feedback for the most recent time request: waiting, approved (with the
    /// granted window) or denied. Resolved requests fade out after an hour.
    @ViewBuilder
    private var requestStatusView: some View {
        if let record = latestRequest, shouldShow(record) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon(for: record))
                    .foregroundStyle(statusColor(for: record))
                Text(statusText(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.isPending {
                    Spacer(minLength: 0)
                    Button("Withdraw") { withdrawRequest() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(statusColor(for: record).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shouldShow(_ record: ChildRequestRecord) -> Bool {
        if record.isPending { return true }
        guard let resolvedAt = record.resolvedAt else { return false }
        return Date().timeIntervalSince(resolvedAt) < 3600
    }

    private func statusText(for record: ChildRequestRecord) -> String {
        let time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        switch record.state {
        case .sent:
            return "Request for \(record.requestedMinutes) min sent at \(time(record.sentAt)) — waiting for parent…"
        case .approved:
            if let until = record.grantedUntil {
                return "Approved — internet on until \(time(until))"
            }
            return "Approved"
        case .denied:
            return "Request denied" + (record.resolvedAt.map { " at \(time($0))" } ?? "")
        }
    }

    private func statusIcon(for record: ChildRequestRecord) -> String {
        switch record.state {
        case .sent: return "clock"
        case .approved: return "checkmark.circle"
        case .denied: return "xmark.circle"
        }
    }

    private func statusColor(for record: ChildRequestRecord) -> Color {
        switch record.state {
        case .sent: return .orange
        case .approved: return .green
        case .denied: return .red
        }
    }

    /// The PIN is checked by the parent's Mac over the authenticated channel; the
    /// parent applies its own brute-force lockout. No PIN hash is ever stored on
    /// a child, so it cannot be recovered offline from this machine.
    private func verifyPIN() {
        guard !pinBusy else { return }
        pinBusy = true
        pinError = ""
        appState.attemptRemoteUnlock(pin: pinEntry) { result in
            pinBusy = false
            switch result {
            case .success:
                showPINPrompt = false
                pinEntry = ""
                pinError = ""
            case .parentUnavailable:
                pinError = isCloud ? "PaCo Cloud cannot be reached." : "Parent's Mac is not connected."
            case .noPIN:
                pinError = "The parent has not set a PIN yet."
            case .lockedOut(let until):
                pinError = "Too many attempts. Try again \(until.formatted(date: .omitted, time: .shortened))."
            case .incorrect:
                pinError = "Incorrect PIN"
            case .error:
                pinError = "Error verifying PIN"
            }
        }
    }

    private func loadUsage() {
        guard let data = try? Data(contentsOf: PaCoFiles.usageFileURL),
              let transfer = try? JSONDecoder().decode(UsageTransfer.self, from: data),
              Calendar.current.isDate(transfer.date, inSameDayAs: Date()) else {
            todayUsage = nil
            return
        }
        todayUsage = transfer
    }

    private func topApps(_ usage: UsageTransfer) -> [AppUsageEntry] {
        Array(usage.appUsage.sorted { $0.duration > $1.duration }.prefix(3))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private func completePairing() {
        let code = pairingCode.trimmingCharacters(in: .whitespaces)
        do {
            // Child stores a single parent key; restart advertising so the TLS-PSK
            // listener uses the real key and the parent can connect.
            try PairingKeyManager.pair(code: code, identity: "parent")
            appState.setController(.localParent, context: modelContext)
            let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            bonjour.restartAdvertising(name: deviceName)
            showPairingPrompt = false
            pairingCode = ""
            pairingError = ""
        } catch {
            pairingError = "Could not pair. Check the code and try again."
        }
    }

    private func sendExtensionRequest() {
        let requestId = UUID()
        if isCloud {
            // The daemon sends it to PaCo Cloud and records it once accepted.
            let minutes = requestMinutes
            daemonClient.cloud(.submitExtensionRequest(requestId: requestId, requestedMinutes: minutes, reason: requestReason)) { response in
                if !response.ok { requestError = response.error ?? "Could not send the request." }
            }
            return
        }
        let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let payload = ExtensionRequestPayload(
            requestId: requestId,
            childDeviceName: deviceName,
            requestedMinutes: requestMinutes,
            reason: requestReason
        )
        guard let payloadData = try? JSONEncoder().encode(payload) else { return }
        // Only record the request once it was handed to a live parent connection;
        // the record is what lets the approval be correlated (and persisted across
        // relaunches) and what the status card shows.
        guard bonjour.sendToParent(PaCoMessage(command: .requestExtension, payload: payloadData)) else {
            requestError = "Parent is not connected. Try again when the parent's PaCo is running."
            return
        }
        requestLog.record(id: requestId, requestedMinutes: requestMinutes, reason: requestReason)
    }
}
