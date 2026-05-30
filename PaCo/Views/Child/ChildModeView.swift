import AppKit
import SwiftUI
import PaCoShared

struct ChildModeView: View {
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @Environment(AppState.self) private var appState
    @State private var showPINPrompt = false
    @State private var pinEntry = ""
    @State private var pinError = ""
    @State private var noPINSet = false

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

                // Footer: parent access + quit
                HStack {
                    Button("Parent Access") {
                        noPINSet = (try? !PINManager.hasPIN()) ?? false
                        showPINPrompt = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit PaCo")
                }
            }
            .padding(30)
            .frame(width: 350, height: 400)
            .onAppear { }

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

    private func verifyPIN() {
        do {
            // If no PIN has been set yet, unlock directly
            guard try PINManager.hasPIN() else {
                showPINPrompt = false
                pinEntry = ""
                pinError = ""
                appState.mode = .parent
                return
            }
            if try PINManager.verifyStoredPIN(pinEntry) {
                showPINPrompt = false
                pinEntry = ""
                pinError = ""
                appState.mode = .parent
            } else {
                pinError = "Incorrect PIN"
            }
        } catch {
            pinError = "Error verifying PIN"
        }
    }
}
