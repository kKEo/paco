import SwiftUI
import SwiftData
import PaCoShared

struct HomeView: View {
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @Query private var profiles: [ChildProfile]
    @Query private var pairings: [PairingInfo]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Home")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if profiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Create a child profile to get started.")
                    )
                } else {
                    ForEach(profiles) { profile in
                        ChildDeviceCard(
                            profile: profile,
                            isInternetEnabled: daemonClient.isInternetEnabled,
                            onToggle: { daemonClient.toggleInternet() }
                        )
                    }
                }
            }
            .padding(24)
        }
    }
}

struct ChildDeviceCard: View {
    let profile: ChildProfile
    let isInternetEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isInternetEnabled ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isInternetEnabled ? "Internet ON" : "Internet OFF")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("Internet", isOn: Binding(
                get: { isInternetEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
}
