// PaCo/Views/Dashboard/AppRulesView.swift
import SwiftUI
import SwiftData
import PaCoShared

struct AppRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restrictions: [AppRestriction]
    @Query private var profiles: [ChildProfile]
    @Query private var schedules: [Schedule]
    @State private var showingAddSheet = false
    @State private var newBundleId = ""
    @State private var newAppName = ""
    @State private var newType: RestrictionType = .blocked
    @State private var newProfile: ChildProfile?
    @State private var newAllowedSchedule: Schedule?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("App Rules")
                        .font(.largeTitle).fontWeight(.bold)
                    Spacer()
                    Button("Add Rule", systemImage: "plus") {
                        newProfile = profiles.first
                        newAllowedSchedule = nil
                        showingAddSheet = true
                    }
                    .disabled(profiles.isEmpty)
                    .help(profiles.isEmpty ? "Create a child profile first" : "Add a rule")
                }

                if restrictions.isEmpty {
                    ContentUnavailableView(
                        "No App Rules",
                        systemImage: "app.badge.checkmark",
                        description: Text("Add restrictions to control which apps can be used.")
                    )
                } else {
                    List {
                        ForEach(restrictions) { restriction in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(restriction.appName).font(.headline)
                                    Text(restriction.bundleIdentifier)
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let profile = restriction.childProfile {
                                        Text(profile.name)
                                            .font(.caption2).foregroundStyle(.blue)
                                    }
                                }
                                Spacer()
                                Text(restriction.restrictionType == .blocked ? "Always Blocked" : "Schedule Only")
                                    .font(.subheadline)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(restriction.restrictionType == .blocked
                                        ? .red.opacity(0.2) : .orange.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { modelContext.delete(restrictions[index]) }
                            try? modelContext.save()
                            SyncManager.shared.syncRestrictions(restrictions)
                        }
                    }
                }
            }
            .padding(24)

            if showingAddSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Add App Restriction").font(.title2).fontWeight(.semibold)

                    TextField("App Name", text: $newAppName).textFieldStyle(.roundedBorder)
                    TextField("Bundle ID (e.g., com.apple.Chess)", text: $newBundleId).textFieldStyle(.roundedBorder)

                    Picker("Profile", selection: $newProfile) {
                        Text("Select profile…").tag(Optional<ChildProfile>.none)
                        ForEach(profiles) { p in Text(p.name).tag(Optional(p)) }
                    }
                    .onChange(of: newProfile) { _, _ in newAllowedSchedule = nil }

                    Picker("Type", selection: $newType) {
                        Text("Always Blocked").tag(RestrictionType.blocked)
                        Text("Schedule Only").tag(RestrictionType.scheduledOnly)
                    }
                    .pickerStyle(.segmented)

                    if newType == .scheduledOnly {
                        let profileSchedules = schedules.filter { $0.childProfile?.id == newProfile?.id }
                        if profileSchedules.isEmpty {
                            Text("No schedules for this profile — create one first.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("Allowed during", selection: $newAllowedSchedule) {
                                Text("Select schedule…").tag(Optional<Schedule>.none)
                                ForEach(profileSchedules) { s in
                                    Text(s.label).tag(Optional(s))
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Cancel") {
                            showingAddSheet = false
                            newBundleId = ""; newAppName = ""
                        }
                        Button("Add") {
                            let r = AppRestriction(
                                bundleIdentifier: newBundleId,
                                appName: newAppName,
                                restrictionType: newType,
                                allowedScheduleId: newAllowedSchedule?.id
                            )
                            r.childProfile = newProfile
                            modelContext.insert(r)
                            try? modelContext.save()
                            SyncManager.shared.syncRestrictions(restrictions)
                            newBundleId = ""; newAppName = ""
                            showingAddSheet = false
                        }
                        .disabled(
                            newBundleId.isEmpty || newAppName.isEmpty || newProfile == nil ||
                            (newType == .scheduledOnly && newAllowedSchedule == nil)
                        )
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30).frame(width: 440)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }
}
