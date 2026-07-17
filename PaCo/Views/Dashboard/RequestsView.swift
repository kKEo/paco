import SwiftUI
import SwiftData
import PaCoShared

struct RequestsView: View {
    @Query(filter: #Predicate<TimeExtensionRequest> { $0.statusRaw == "pending" },
           sort: \TimeExtensionRequest.requestedAt, order: .reverse)
    private var pendingRequests: [TimeExtensionRequest]

    @Query(filter: #Predicate<TimeExtensionRequest> { $0.statusRaw != "pending" },
           sort: \TimeExtensionRequest.requestedAt, order: .reverse)
    private var resolvedRequests: [TimeExtensionRequest]

    @EnvironmentObject private var bonjour: BonjourService
    @EnvironmentObject private var daemonClient: DaemonXPCClient
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Requests")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if pendingRequests.isEmpty && resolvedRequests.isEmpty {
                    ContentUnavailableView(
                        "No Requests",
                        systemImage: "clock.badge.checkmark",
                        description: Text("Time extension requests from child devices will appear here.")
                    )
                } else {
                    if !pendingRequests.isEmpty {
                        Text("Pending").font(.headline).foregroundStyle(.secondary)
                        ForEach(pendingRequests) { req in
                            RequestRow(request: req, onApprove: { approve(req) }, onDeny: { deny(req) })
                        }
                    }

                    if !resolvedRequests.isEmpty {
                        Text("Resolved").font(.headline).foregroundStyle(.secondary)
                        ForEach(Array(resolvedRequests.prefix(20)), id: \.id) { req in
                            RequestRow(request: req, onApprove: nil, onDeny: nil)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func approve(_ req: TimeExtensionRequest) {
        req.status = .approved
        req.respondedAt = Date()
        try? context.save()

        // Grant the requested minutes to the specific child that asked. The child
        // turns this into a temporary override window that its own agent enforces.
        let payload = ExtensionResponsePayload(
            requestId: req.id, status: .approved, grantedMinutes: req.requestedMinutes
        )
        if let data = try? JSONEncoder().encode(payload) {
            bonjour.send(PaCoMessage(command: .approveExtension, payload: data), to: req.childDeviceName)
        }
    }

    private func deny(_ req: TimeExtensionRequest) {
        req.status = .denied
        req.respondedAt = Date()
        try? context.save()

        let payload = ExtensionResponsePayload(requestId: req.id, status: .denied)
        if let data = try? JSONEncoder().encode(payload) {
            bonjour.send(PaCoMessage(command: .denyExtension, payload: data), to: req.childDeviceName)
        }
    }
}

struct RequestRow: View {
    let request: TimeExtensionRequest
    let onApprove: (() -> Void)?
    let onDeny: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(request.childDeviceName) — \(request.requestedMinutes) min")
                    .font(.headline)
                if !request.reason.isEmpty {
                    Text(request.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(request.requestedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let approve = onApprove, let deny = onDeny {
                Button("Approve") { approve() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Deny") { deny() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
            } else {
                Text(request.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 1)
    }

    private var statusIcon: String {
        switch request.status {
        case .pending: return "clock"
        case .approved: return "checkmark.circle"
        case .denied: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch request.status {
        case .pending: return .orange
        case .approved: return .green
        case .denied: return .red
        }
    }
}
