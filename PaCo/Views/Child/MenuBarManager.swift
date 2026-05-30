import AppKit
import SwiftUI
import PaCoShared

final class MenuBarManager: ObservableObject {

    @Published var isInternetEnabled = true
    @Published var isGracePeriod = false
    @Published var graceRemainingSeconds = 0
    @Published var nextScheduleChange = ""

    private var statusItem: NSStatusItem?
    private let logger = PaCoLogger.app

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "PaCo")
        }
        updateIcon()
        statusItem = item
        logger.info("Menu bar icon set up")
    }

    func updateStatus(internetEnabled: Bool, gracePeriod: Bool = false, graceSeconds: Int = 0, nextChange: String = "") {
        self.isInternetEnabled = internetEnabled
        self.isGracePeriod = gracePeriod
        self.graceRemainingSeconds = graceSeconds
        self.nextScheduleChange = nextChange
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let color: NSColor
        let imageName: String

        if isGracePeriod {
            color = .systemYellow
            imageName = "shield.checkered"
        } else if isInternetEnabled {
            color = .systemGreen
            imageName = "shield.checkered"
        } else {
            color = .systemRed
            imageName = "shield.checkered"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            .applying(.init(paletteColors: [color]))
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "PaCo")?
            .withSymbolConfiguration(config)
    }

    func tearDown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
}
