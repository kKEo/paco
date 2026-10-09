import SwiftUI
import PaCoShared

/// PIN prompt shown in place of the parent dashboard until the parent unlocks it.
struct ParentUnlockView: View {
    @Environment(AppState.self) private var appState
    @State private var pin = ""
    @State private var error = ""
    @State private var noPIN = false
    @State private var showSetup = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Parent PIN")
                    .font(.title2)
                    .fontWeight(.semibold)

                if noPIN {
                    Text("No parent PIN is stored on this Mac. Create one to open the dashboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create PIN") { showSetup = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    SecureField("6-digit PIN", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(unlock)
                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    Button("Unlock", action: unlock)
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.isEmpty)
                }
            }
            .padding(40)
            .frame(minWidth: 360, minHeight: 320)

            if showSetup {
                Color.black.opacity(0.3).ignoresSafeArea()
                ParentPINSetupView(onCancel: { showSetup = false }) {
                    showSetup = false
                    noPIN = false
                    appState.unlock()
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
        .onAppear {
            pin = ""
            error = ""
            noPIN = (try? PINManager.hasPIN()) != true
            if let until = PINManager.lockedOutUntil() {
                error = lockoutMessage(until)
            }
        }
    }

    private func unlock() {
        switch appState.attemptUnlock(pin: pin) {
        case .success:
            pin = ""
            error = ""
        case .incorrect:
            error = "Incorrect PIN"
        case .lockedOut(let until):
            error = lockoutMessage(until)
        case .noPIN:
            noPIN = true
        case .error, .parentUnavailable:
            error = "Error verifying PIN"
        }
        if error.isEmpty == false { pin = "" }
    }

    private func lockoutMessage(_ until: Date) -> String {
        "Too many attempts. Try again at \(until.formatted(date: .omitted, time: .shortened))."
    }
}
