import SwiftUI
import PaCoShared

struct RoleSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var showParentPINSetup = false
    @State private var childSetup: ChildSetupStep?

    private enum ChildSetupStep { case choose, cloud }

    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Text("Welcome to PaCo")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Parental Control for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 30) {
                    RoleCard(
                        title: "Set up as Parent",
                        description: "Manage schedules, app rules, and monitor usage.",
                        systemImage: "person.badge.shield.checkmark",
                        action: { showParentPINSetup = true }
                    )

                    RoleCard(
                        title: "Set up as Child",
                        description: "This Mac will be monitored and controlled by a parent.",
                        systemImage: "person.crop.circle",
                        action: { childSetup = .choose }
                    )
                }
            }
            .padding(60)
            .frame(minWidth: 600, minHeight: 400)

            if showParentPINSetup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ParentPINSetupView(onCancel: { showParentPINSetup = false }) {
                    appState.completeSetup(role: .parent, context: modelContext)
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }

            if let step = childSetup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                Group {
                    switch step {
                    case .choose:
                        ChildControllerChoiceView(
                            onLocalParent: { appState.completeSetup(role: .child, controller: .localParent, context: modelContext) },
                            onCloud: { childSetup = .cloud },
                            onCancel: { childSetup = nil })
                    case .cloud:
                        CloudEnrollView(
                            onCancel: { childSetup = .choose },
                            onEnrolled: { appState.completeSetup(role: .child, controller: .cloud, context: modelContext) })
                    }
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
        }
    }
}

/// Child onboarding: who will manage this Mac.
struct ChildControllerChoiceView: View {
    let onLocalParent: () -> Void
    let onCloud: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Who manages this Mac?").font(.title2).fontWeight(.semibold)
            VStack(spacing: 12) {
                choice(
                    title: "A parent's Mac nearby",
                    detail: "The parent runs PaCo on their own Mac on the same network and pairs with a code.",
                    systemImage: "laptopcomputer.and.iphone",
                    action: onLocalParent)
                choice(
                    title: "PaCo Cloud, from a browser",
                    detail: "The parent manages this Mac and sees its screen time on a PaCo Cloud web page.",
                    systemImage: "cloud",
                    action: onCloud)
            }
            Button("Back", action: onCancel)
        }
        .padding(30)
        .frame(width: 420)
    }

    private func choice(title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct ParentPINSetupView: View {
    let onCancel: () -> Void
    let onComplete: () -> Void
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Parent PIN")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This 6-digit PIN protects parent settings.")
                .foregroundStyle(.secondary)

            SecureField("Enter 6-digit PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            SecureField("Confirm PIN", text: $confirmPIN)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            if !error.isEmpty {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack(spacing: 16) {
                Button("Cancel") { onCancel() }
                Button("Create") { createPIN() }
                    .disabled(pin.count != 6 || confirmPIN.count != 6)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 350)
    }

    private func createPIN() {
        guard pin == confirmPIN else {
            error = "PINs do not match"
            return
        }
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            error = "PIN must be exactly 6 digits"
            return
        }
        do {
            try PINManager.storePIN(pin)
            onComplete()
        } catch {
            self.error = "Failed to save PIN: \(error.localizedDescription)"
        }
    }
}

struct RoleCard: View {
    let title: String
    let description: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .frame(width: 250, height: 250)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }
}
