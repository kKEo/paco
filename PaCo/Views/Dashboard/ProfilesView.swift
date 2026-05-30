// PaCo/Views/Dashboard/ProfilesView.swift
import SwiftUI
import SwiftData
import PaCoShared

struct ProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var profiles: [ChildProfile]
    @Query private var deviceConfigs: [DeviceConfig]
    @State private var showingAddSheet = false
    @State private var newProfileName = ""

    private var activeProfileId: UUID? {
        deviceConfigs.first?.childProfileId
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Profiles")
                        .font(.largeTitle).fontWeight(.bold)
                    Spacer()
                    Button("Add Profile", systemImage: "plus") {
                        showingAddSheet = true
                    }
                }

                if profiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add a child profile to get started.")
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        ForEach(profiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: profile.id == activeProfileId,
                                onSetActive: {
                                    appState.setActiveProfile(id: profile.id, context: modelContext)
                                },
                                onDelete: {
                                    if activeProfileId == profile.id {
                                        appState.setActiveProfile(id: nil, context: modelContext)
                                    }
                                    modelContext.delete(profile)
                                    try? modelContext.save()
                                }
                            )
                        }
                    }
                }
            }
            .padding(24)

            if showingAddSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("New Child Profile")
                        .font(.title2).fontWeight(.semibold)
                    TextField("Child's name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder).frame(width: 250)
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            showingAddSheet = false; newProfileName = ""
                        }
                        Button("Create") {
                            let profile = ChildProfile(name: newProfileName)
                            modelContext.insert(profile)
                            try? modelContext.save()
                            // Auto-set active if this is the first profile
                            if profiles.isEmpty {
                                appState.setActiveProfile(id: profile.id, context: modelContext)
                            }
                            newProfileName = ""
                            showingAddSheet = false
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30).frame(width: 350)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }
}

struct ProfileCard: View {
    let profile: ChildProfile
    let isActive: Bool
    let onSetActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48)).foregroundStyle(.blue)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: -4)
                }
            }
            Text(profile.name).font(.headline)
            HStack(spacing: 12) {
                Label("\(profile.schedules.count)", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(profile.appRestrictions.count)", systemImage: "app.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !isActive {
                Button("Set as Active") { onSetActive() }
                    .font(.caption).buttonStyle(.bordered)
            } else {
                Text("Active on this device")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding(20)
        .frame(width: 200)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: isActive ? 4 : 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.green.opacity(0.5) : .clear, lineWidth: 2)
        )
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
