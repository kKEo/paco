import SwiftUI
import SwiftData
import Network
import PaCoShared

struct DevicesView: View {
    @Query private var pairings: [PairingInfo]
    @StateObject private var bonjour = BonjourService()
    @Environment(\.modelContext) private var context

    @State private var showPairOverlay = false
    @State private var newDeviceName = ""

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
                                let name = deviceName(from: result)
                                let info = PairingInfo(
                                    parentDeviceName: Host.current().localizedName ?? "Parent",
                                    childDeviceName: name
                                )
                                context.insert(info)
                                try? context.save()
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
                    TextField("Child device name", text: $newDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    HStack {
                        Button("Cancel") {
                            showPairOverlay = false
                            newDeviceName = ""
                        }
                        Button("Pair") {
                            let name = newDeviceName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            let info = PairingInfo(
                                parentDeviceName: Host.current().localizedName ?? "Parent",
                                childDeviceName: name
                            )
                            context.insert(info)
                            try? context.save()
                            showPairOverlay = false
                            newDeviceName = ""
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
        }
        .onAppear { bonjour.startBrowsing() }
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
