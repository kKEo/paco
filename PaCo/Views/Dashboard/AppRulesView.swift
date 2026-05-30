import SwiftUI
import SwiftData
import PaCoShared

struct AppRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restrictions: [AppRestriction]
    @State private var showingAddSheet = false
    @State private var newBundleId = ""
    @State private var newAppName = ""
    @State private var newType: RestrictionType = .blocked

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("App Rules")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Add Rule", systemImage: "plus") {
                        showingAddSheet = true
                    }
                }

                if restrictions.isEmpty {
                    ContentUnavailableView(
                        "No App Rules",
                        systemImage: "app.badge.checkmark",
                        description: Text("Add app restrictions to control which apps can be used.")
                    )
                } else {
                    List {
                        ForEach(restrictions) { restriction in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(restriction.appName).font(.headline)
                                    Text(restriction.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(restriction.restrictionType == .blocked ? "Blocked" : "Schedule Only")
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(restriction.restrictionType == .blocked ? .red.opacity(0.2) : .orange.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { modelContext.delete(restrictions[index]) }
                        }
                    }
                }
            }
            .padding(24)

            if showingAddSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Add App Restriction").font(.title2).fontWeight(.semibold)
                    TextField("App Name", text: $newAppName).textFieldStyle(.roundedBorder)
                    TextField("Bundle Identifier (e.g., com.example.app)", text: $newBundleId).textFieldStyle(.roundedBorder)
                    Picker("Type", selection: $newType) {
                        Text("Always Blocked").tag(RestrictionType.blocked)
                        Text("Schedule Only").tag(RestrictionType.scheduledOnly)
                    }
                    HStack {
                        Button("Cancel") { showingAddSheet = false }
                        Button("Add") {
                            let r = AppRestriction(bundleIdentifier: newBundleId, appName: newAppName, restrictionType: newType)
                            modelContext.insert(r)
                            newBundleId = ""
                            newAppName = ""
                            showingAddSheet = false
                        }
                        .disabled(newBundleId.isEmpty || newAppName.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30)
                .frame(width: 400)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }
}
