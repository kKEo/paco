import SwiftUI
import PaCoShared

/// Enroll this child Mac with PaCo Cloud: the parent creates a one-time code on
/// the PaCo Cloud web page; it is typed here and redeemed by the root daemon,
/// which keeps the resulting device token where the child cannot read it.
struct CloudEnrollView: View {
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    let onCancel: () -> Void
    let onEnrolled: () -> Void

    /// Remembered so a re-enrollment does not need the address typed again.
    private static let lastServerKey = "PaCoCloudLastServer"

    @State private var serverURL = UserDefaults.standard.string(forKey: CloudEnrollView.lastServerKey) ?? ""
    @State private var code = ""
    @State private var deviceName = AppDelegate.deviceName
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Connect to PaCo Cloud").font(.headline)
            Text("On the parent's PaCo Cloud page, choose Add a Mac and type the code shown there.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Server address", text: $serverURL, prompt: Text(CloudServerURL.placeholder))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField("Code", text: $code, prompt: Text("ABCD-1234"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("Name of this Mac", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 260)
            .disabled(busy)

            if !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: onCancel).disabled(busy)
                Button(busy ? "Connecting…" : "Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !canSubmit)
            }
        }
        .padding(30)
        .frame(width: 330)
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func connect() {
        busy = true
        error = ""
        daemonClient.cloud(.enroll(serverURL: serverURL, code: code, deviceName: deviceName)) { response in
            busy = false
            guard response.ok else {
                error = response.error ?? "Could not connect to PaCo Cloud."
                return
            }
            UserDefaults.standard.set(serverURL.trimmingCharacters(in: .whitespaces), forKey: Self.lastServerKey)
            code = ""
            onEnrolled()
        }
    }
}
