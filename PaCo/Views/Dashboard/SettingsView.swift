import SwiftUI
import SwiftData
import PaCoShared

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @Query private var deviceConfigs: [DeviceConfig]
    @State private var showCloudDisconnectConfirm = false
    @State private var cloudMessage = ""

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var message = ""
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle).fontWeight(.bold)

                GroupBox("Change PIN") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Current PIN", text: $currentPIN)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        SecureField("New PIN (6 digits)", text: $newPIN)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button("Update PIN") {
                            changePIN()
                        }
                        .disabled(currentPIN.isEmpty || newPIN.count != 6 || !newPIN.allSatisfy(\.isNumber))

                        if !message.isEmpty {
                            Text(message)
                                .foregroundStyle(message.contains("Success") ? .green : .red)
                                .font(.caption)
                        }
                    }
                    .padding(12)
                }

                if appState.role == .child, appState.controller == .cloud {
                    GroupBox("PaCo Cloud") {
                        cloudSection.padding(12)
                    }
                }

                GroupBox("Device Role") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reset this device to choose a new role (Parent or Child). This clears all local data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reset & Change Role…", role: .destructive) {
                            showResetConfirm = true
                        }
                    }
                    .padding(12)
                }
            }
            .padding(24)

            if showCloudDisconnectConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Disconnect from PaCo Cloud?")
                        .font(.headline)
                    Text("This Mac stops reporting screen time and taking commands from PaCo Cloud. The rules it has now keep applying until a parent Mac or PaCo Cloud manages it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button("Cancel") { showCloudDisconnectConfirm = false }
                        Button("Disconnect", role: .destructive) {
                            showCloudDisconnectConfirm = false
                            disconnectFromCloud()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(30)
                .frame(width: 380)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }

            if showResetConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Reset device role?")
                        .font(.headline)
                    Text("This will remove all profiles, schedules, and restrictions stored on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button("Cancel") { showResetConfirm = false }
                        Button("Reset & Change Role", role: .destructive) {
                            showResetConfirm = false
                            resetRole()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(30)
                .frame(width: 360)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cloud = daemonClient.cloudStatus, cloud.enrolled {
                Text("This Mac is managed from PaCo Cloud at \(cloud.serverURL?.host ?? "?") as “\(cloud.deviceName ?? "?")”.")
                    .font(.caption)
                Text(cloud.connected ? "Connected." : (cloud.lastError ?? "Not reachable right now."))
                    .font(.caption)
                    .foregroundStyle(cloud.connected ? Color.secondary : Color.orange)
                Text("Schedules, app rules and the parent PIN are managed on the PaCo Cloud web page, not here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Disconnect from PaCo Cloud…", role: .destructive) { showCloudDisconnectConfirm = true }
            } else {
                Text(daemonClient.cloudStatus?.lastError ?? "This Mac is not connected to PaCo Cloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !cloudMessage.isEmpty {
                Text(cloudMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { daemonClient.refreshCloudStatus() }
    }

    private func disconnectFromCloud() {
        cloudMessage = ""
        daemonClient.cloud(.unenroll) { response in
            guard response.ok else {
                cloudMessage = response.error ?? "Could not disconnect."
                return
            }
            appState.setController(.localParent, context: modelContext)
        }
    }

    private func changePIN() {
        do {
            guard try PINManager.verifyStoredPIN(currentPIN) else {
                message = "Current PIN is incorrect"
                return
            }
            try PINManager.storePIN(newPIN)
            message = "Success: PIN updated"
            currentPIN = ""
            newPIN = ""
        } catch {
            message = "Error: \(error.localizedDescription)"
        }
    }

    private func resetRole() {
        // Delete all DeviceConfig records so the app returns to onboarding
        for config in deviceConfigs {
            modelContext.delete(config)
        }
        try? modelContext.save()
        appState.mode = .onboarding
    }
}
