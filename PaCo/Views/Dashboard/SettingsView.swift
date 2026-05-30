import SwiftUI
import PaCoShared

struct SettingsView: View {
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var message = ""

    var body: some View {
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
        }
        .padding(24)
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
}
