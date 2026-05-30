import SwiftUI
import SwiftData
import PaCoShared

struct DevicesView: View {
    @Query private var pairings: [PairingInfo]
    @StateObject private var bonjour = BonjourService()
    @State private var showingPairSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Devices").font(.largeTitle).fontWeight(.bold)
                Spacer()
                Button("Pair New Device", systemImage: "plus") {
                    showingPairSheet = true
                }
            }

            if pairings.isEmpty {
                ContentUnavailableView(
                    "No Paired Devices",
                    systemImage: "laptopcomputer.trianglebadge.exclamationmark",
                    description: Text("Pair a child device to start managing it.")
                )
            } else {
                List(pairings) { pairing in
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(pairing.childDeviceName).font(.headline)
                            Text("Paired \(pairing.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
