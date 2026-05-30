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
        guard browser == nil else { return }
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
        // Step 1: Read exactly 4 bytes for the length header
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] headerData, _, _, error in
            guard let self else { return }

            if let error {
                self.logger.error("Receive header error: \(error)")
                return
            }

            guard let headerData, headerData.count == 4 else {
                self.logger.warning("Incomplete header received")
                return
            }

            // Parse length from big-endian 4-byte header
            let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 1_048_576 else {  // Max 1MB message
                self.logger.warning("Invalid message length: \(length)")
                return
            }

            // Step 2: Read exactly `length` bytes for the message body
            let messageLength = Int(length)
            connection.receive(minimumIncompleteLength: messageLength, maximumLength: messageLength) { [weak self] bodyData, _, _, bodyError in
                guard let self else { return }

                if let bodyError {
                    self.logger.error("Receive body error: \(bodyError)")
                    return
                }

                guard let bodyData, bodyData.count == messageLength else {
                    self.logger.warning("Incomplete body: expected \(messageLength) bytes")
                    return
                }

                if let response = try? JSONDecoder().decode(PaCoResponse.self, from: bodyData) {
                    handler(response)
                } else {
                    self.logger.warning("Failed to decode PaCoResponse from \(messageLength) bytes")
                }

                // Continue receiving next message
                self.receiveMessages(on: connection, handler: handler)
            }
        }
    }
}
