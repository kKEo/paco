import SwiftUI
import SwiftData
import PaCoShared

enum AppMode: Equatable {
    case onboarding
    case parent
    case child
}

@Observable
final class AppState {
    var mode: AppMode = .onboarding
    var showPINEntry = false

    private let logger = PaCoLogger.app

    func determineMode(context: ModelContext) {
        let descriptor = FetchDescriptor<DeviceConfig>()
        guard let config = try? context.fetch(descriptor).first else {
            mode = .onboarding
            return
        }
        mode = config.role == .parent ? .parent : .child
        let currentMode = mode
        logger.info("App mode: \(String(describing: currentMode))")
    }

    func completeSetup(role: DeviceRole, context: ModelContext) {
        let config = DeviceConfig(role: role)
        context.insert(config)
        try? context.save()
        mode = role == .parent ? .parent : .child
        logger.info("Setup complete as \(role.rawValue)")
    }
}
