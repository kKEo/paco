import SwiftUI
import SwiftData
import Network
import PaCoShared

struct DevicesView: View {
    @Query private var pairings: [PairingInfo]
    @EnvironmentObject var bonjour: BonjourService
    @Environment(\.modelContext) private var context

    @State private var showPairOverlay = false
    @State private var newDeviceName = ""
    @State private var generatedCode: String?
    @State private var pairingForName = ""

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Devices").font(.largeTitle).fontWeight(.bold)
                        Spacer()
                        Button("Pair New Device", systemImage: "plus") {
                            showPairOverlay = true
                        }
                    }

                    if !pairings.isEmpty {
                        Text("Paired Devices")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(pairings) { pairing in
                            PairedDeviceRow(
                                pairing: pairing,
                                onlineEndpoint: onlineEndpoint(for: pairing),
                                onConnect: { endpoint in
                                    bonjour.connect(
                                        to: endpoint,
                                        identity: pairing.childDeviceName,
                                        responseHandler: { _ in },
                                        incomingMessageHandler: { _ in }
                                    )
                                },
                                onRemove: {
                                    context.delete(pairing)
                                    try? context.save()
                                }
                            )
                        }
                    }

                    let unpaired = bonjour.discoveredDevices.filter { result in
                        let name = deviceName(from: result)
                        return !pairings.contains(where: { $0.childDeviceName == name })
                    }
                    if !unpaired.isEmpty {
                        Text("Nearby Devices (Not Paired)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(unpaired, id: \.self) { result in
                            DiscoveredDeviceRow(result: result) {
                                beginPairing(name: deviceName(from: result))
                            }
                        }
                    }

                    if pairings.isEmpty && bonjour.discoveredDevices.isEmpty {
                        ContentUnavailableView(
                            "No Devices Found",
                            systemImage: "laptopcomputer.trianglebadge.exclamationmark",
                            description: Text("Start PaCo in child mode on another Mac and it will appear here.")
                        )
                    }
                }
                .padding(24)
            }

            if showPairOverlay {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Pair New Device").font(.headline)
                    Text("Enter the child device's name, then share the pairing code with it.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    TextField("Child device name", text: $newDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    HStack {
                        Button("Cancel") {
                            showPairOverlay = false
                            newDeviceName = ""
                        }
                        Button("Generate Code") {
                            let name = newDeviceName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            showPairOverlay = false
                            newDeviceName = ""
                            beginPairing(name: name)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newDeviceName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(30)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }

            if let code = generatedCode {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Pairing Code").font(.headline)
                    Text("On \(pairingForName), tap “Pair with Parent” and enter:")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                    Text("This code is valid for this pairing only.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button("Done") { generatedCode = nil }
                        .buttonStyle(.borderedProminent)
                }
                .padding(30)
                .frame(width: 360)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
        .onAppear { bonjour.startBrowsing() }
        .onChange(of: bonjour.discoveredDevices) { _, _ in autoConnectPairedDevices() }
    }

    /// Generate a one-time code, derive & store the pairing key under the child's
    /// name, and record the pairing. The user reads the code aloud / types it on
    /// the child, which derives the same key.
    private func beginPairing(name: String) {
        let code = PairingKeyManager.generateCode()
        try? PairingKeyManager.pair(code: code, identity: name)
        if !pairings.contains(where: { $0.childDeviceName == name }) {
            let info = PairingInfo(
                parentDeviceName: Host.current().localizedName ?? "Parent",
                childDeviceName: name
            )
            context.insert(info)
            try? context.save()
        }
        pairingForName = name
        generatedCode = code
    }

    /// Auto-connect to any paired, online device we're not already connected to,
    /// so child requests arrive without the parent clicking Connect.
    private func autoConnectPairedDevices() {
        for pairing in pairings {
            guard !bonjour.isConnected(to: pairing.childDeviceName),
                  let endpoint = onlineEndpoint(for: pairing) else { continue }
            bonjour.connect(
                to: endpoint,
                identity: pairing.childDeviceName,
                responseHandler: { _ in },
                incomingMessageHandler: { _ in }
            )
        }
    }

    private func deviceName(from result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint {
            return name
        }
        return result.endpoint.debugDescription
    }

    private func onlineEndpoint(for pairing: PairingInfo) -> NWEndpoint? {
        bonjour.discoveredDevices.first(where: { deviceName(from: $0) == pairing.childDeviceName })?.endpoint
    }
}

struct PairedDeviceRow: View {
    let pairing: PairingInfo
    let onlineEndpoint: NWEndpoint?
    let onConnect: (NWEndpoint) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "laptopcomputer")
                .font(.title2)
                .foregroundStyle(onlineEndpoint != nil ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(pairing.childDeviceName).font(.headline)
                Text(onlineEndpoint != nil ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundStyle(onlineEndpoint != nil ? .green : .secondary)
            }

            Spacer()

            if let endpoint = onlineEndpoint {
                Button("Connect") { onConnect(endpoint) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(role: .destructive) { onRemove() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 1)
    }
}

struct DiscoveredDeviceRow: View {
    let result: NWBrowser.Result
    let onPair: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "laptopcomputer.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                if case .service(let name, _, _, _) = result.endpoint {
                    Text(name).font(.headline)
                } else {
                    Text(result.endpoint.debugDescription).font(.headline)
                }
                Text("Discovered nearby").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Pair") { onPair() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 1)
    }
}
