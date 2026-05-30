import SwiftUI
import SwiftData
import PaCoShared

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var deviceConfigs: [DeviceConfig]

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
