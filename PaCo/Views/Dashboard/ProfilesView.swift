import SwiftUI
import SwiftData
import PaCoShared

struct ProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @State private var showingAddSheet = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Profiles")
                    .font(.largeTitle)
                    .fontWeight(.bold)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    ForEach(profiles) { profile in
                        ProfileCard(profile: profile, onDelete: {
                            modelContext.delete(profile)
                        })
                    }
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $showingAddSheet) {
            AddProfileSheet(name: $newProfileName) {
                let profile = ChildProfile(name: newProfileName)
                modelContext.insert(profile)
                newProfileName = ""
                showingAddSheet = false
            }
        }
    }
}

struct ProfileCard: View {
    let profile: ChildProfile
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text(profile.name)
                .font(.headline)
            Text("Created \(profile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 200, height: 160)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct AddProfileSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Child Profile")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Child's name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                Button("Create") { onSave() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}
