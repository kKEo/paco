import SwiftUI
import SwiftData
import PaCoShared

struct HomeView: View {
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @Query private var profiles: [ChildProfile]
    @Query private var pairings: [PairingInfo]
    @Query(filter: #Predicate<TimeExtensionRequest> { $0.statusRaw == "pending" })
    private var pendingRequests: [TimeExtensionRequest]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Home")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if !pendingRequests.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("\(pendingRequests.count) pending time request\(pendingRequests.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(14)
                    .background(.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let manual = daemonClient.manualOverride {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised")
                            .foregroundStyle(.blue)
                        Text("Manual: internet \(manual.enabled ? "ON" : "OFF") until \(manual.until.formatted(date: .omitted, time: .shortened)), then back to the schedule")
                            .font(.subheadline)
                        Spacer()
                        Button("Back to schedule") { daemonClient.clearManualOverride() }
                            .controlSize(.small)
                    }
                    .padding(14)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

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
        .onAppear { daemonClient.refreshStatus() }
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
