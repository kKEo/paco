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
    @State private var noPINSet = false
    @State private var showRequestOverlay = false
    @State private var requestMinutes = 30
    @State private var requestReason = ""
    @State private var showPairingPrompt = false
    @State private var pairingCode = ""
    @State private var pairingError = ""
    @State private var todayUsage: UsageTransfer?
    @State private var usageRefreshTimer: Timer?

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
                        .fill(bonjour.isParentConnected ? .green : (isPaired ? .orange : .secondary))
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

                if requestLog.pending == nil {
                    Button("Request More Time") {
                        requestError = ""
                        showRequestOverlay = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bonjour.isParentConnected)
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
                    Button("Pair with Parent") {
                        pairingCode = ""
                        pairingError = ""
                        showPairingPrompt = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Parent Access") {
                        noPINSet = (try? !PINManager.hasPIN()) ?? false
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
            }
            .onDisappear {
                usageRefreshTimer?.invalidate()
                usageRefreshTimer = nil
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

            if showPINPrompt {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Enter Parent PIN").font(.headline)
                    if noPINSet {
                        Text("No PIN set — tap Unlock to continue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("PIN", text: $pinEntry)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                    }
                    if !pinError.isEmpty {
                        Text(pinError).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        Button("Cancel") {
                            showPINPrompt = false
                            pinEntry = ""
                            pinError = ""
                        }
                        Button("Unlock") {
                            verifyPIN()
                        }
                        .buttonStyle(.borderedProminent)
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

    private var parentStatusText: String {
        if bonjour.isParentConnected { return "Connected to parent" }
        return isPaired ? "Paired — parent not connected" : "Not paired with a parent"
    }

    /// Feedback for the most recent time request: waiting, approved (with the
    /// granted window) or denied. Resolved requests fade out after an hour.
    @ViewBuilder
    private var requestStatusView: some View {
        if let record = requestLog.latest, shouldShow(record) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon(for: record))
                    .foregroundStyle(statusColor(for: record))
                Text(statusText(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.isPending {
                    Spacer(minLength: 0)
                    Button("Withdraw") { requestLog.withdrawPending() }
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

    private func verifyPIN() {
        // Verification + lockout live in AppState so the child-device unlock and the
        // parent dashboard gate behave identically. A child device with no
        // provisioned parent PIN cannot be unlocked locally; pair with a parent first.
        switch appState.attemptUnlock(pin: pinEntry) {
        case .success:
            showPINPrompt = false
            pinEntry = ""
            pinError = ""
        case .noPIN:
            pinError = "No parent PIN on this device. Pair with a parent first."
        case .lockedOut(let until):
            pinError = "Too many attempts. Try again \(until.formatted(date: .omitted, time: .shortened))."
        case .incorrect:
            pinError = "Incorrect PIN"
        case .error:
            pinError = "Error verifying PIN"
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
        let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let requestId = UUID()
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
