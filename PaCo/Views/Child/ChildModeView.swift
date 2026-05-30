import SwiftUI
import PaCoShared

struct ChildModeView: View {
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var daemonClient = DaemonXPCClient()
    @State private var showPINPrompt = false
    @State private var pinEntry = ""
    @State private var pinError = ""

    var body: some View {
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

            // Schedule info
            Text("PaCo is monitoring this device")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            // Today's usage
            VStack(spacing: 8) {
                Text("Today's Usage")
                    .font(.headline)
                Text("Usage data will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Parent access
            Button("Parent Access") {
                showPINPrompt = true
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 350, height: 400)
        .onAppear {
            menuBarManager.setup()
            daemonClient.connect()
        }
        .onDisappear {
            menuBarManager.tearDown()
        }
        .onChange(of: daemonClient.isInternetEnabled) { _, newValue in
            menuBarManager.updateStatus(internetEnabled: newValue)
        }
        .sheet(isPresented: $showPINPrompt) {
            VStack(spacing: 16) {
                Text("Enter Parent PIN").font(.headline)
                SecureField("PIN", text: $pinEntry)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
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
        }
    }

    private func verifyPIN() {
        do {
            if try PINManager.verifyStoredPIN(pinEntry) {
                showPINPrompt = false
                pinEntry = ""
                pinError = ""
                // Switch to parent mode would go here
            } else {
                pinError = "Incorrect PIN"
            }
        } catch {
            pinError = "Error verifying PIN"
        }
    }
}
