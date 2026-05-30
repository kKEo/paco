import Foundation
import Network
import PaCoShared

/// Manages Bonjour discovery and TLS-secured communication between parent and child devices.
final class BonjourService: ObservableObject {

    @Published var discoveredDevices: [NWBrowser.Result] = []
    @Published var isListening = false

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let logger = PaCoLogger.network

    private let serviceType = "_paco._tcp"
    private let serviceDomain = "local."

    // MARK: - Advertise (child mode)

    func startAdvertising(name: String) {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: name, type: serviceType, domain: serviceDomain)

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logger.info("Bonjour: advertising as '\(name)'")
                    DispatchQueue.main.async { self?.isListening = true }
                case .failed(let error):
                    self?.logger.error("Bonjour listener failed: \(error)")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            logger.error("Failed to start Bonjour listener: \(error)")
        }
    }

    // MARK: - Browse (parent mode)

    func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: .tcp)

        browser.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.logger.info("Bonjour: browsing for devices")
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredDevices = Array(results)
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    // MARK: - Connect (parent to child)

    func connect(to endpoint: NWEndpoint, messageHandler: @escaping (PaCoResponse) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Connected to child device")
                self?.receiveMessages(on: connection, handler: messageHandler)
            case .failed(let error):
                self?.logger.error("Connection failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: .main)
        activeConnection = connection
    }

    func send(message: PaCoMessage) {
        guard let connection = activeConnection else {
            logger.warning("No active connection to send message")
            return
        }
        do {
            let data = try message.encoded()
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.error("Send failed: \(error)")
                }
            })
        } catch {
            logger.error("Message encoding failed: \(error)")
        }
    }

    // MARK: - Stop

    func stop() {
        browser?.cancel()
        listener?.cancel()
        activeConnection?.cancel()
        browser = nil
        listener = nil
        activeConnection = nil
        DispatchQueue.main.async {
            self.discoveredDevices = []
            self.isListening = false
        }
    }

    // MARK: - Private

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.logger.info("Accepted incoming connection")
            }
        }
        connection.start(queue: .main)
        activeConnection = connection
    }

    private func receiveMessages(on connection: NWConnection, handler: @escaping (PaCoResponse) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data, data.count > 4 {
                if let response = try? JSONDecoder().decode(PaCoResponse.self, from: data.dropFirst(4)) {
                    handler(response)
                }
            }
            if error == nil {
                self?.receiveMessages(on: connection, handler: handler)
            }
        }
    }
}
