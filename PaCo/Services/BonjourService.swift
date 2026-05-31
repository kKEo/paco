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

    /// Called when this device receives an inbound PaCoMessage (from parent on child side, or from child on parent side).
    var onIncomingMessage: ((PaCoMessage) -> Void)?

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

    /// Connect to a child endpoint.
    /// - responseHandler: called when a PaCoResponse frame arrives (reply to commands we sent).
    /// - incomingMessageHandler: called when a PaCoMessage frame arrives (child-initiated, e.g. requestExtension).
    func connect(
        to endpoint: NWEndpoint,
        responseHandler: @escaping (PaCoResponse) -> Void,
        incomingMessageHandler: @escaping (PaCoMessage) -> Void
    ) {
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Connected to child device")
                self?.receiveFrames(on: connection, responseHandler: responseHandler, messageHandler: incomingMessageHandler)
            case .failed(let error):
                self?.logger.error("Connection failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: .main)
        activeConnection = connection
    }

    // MARK: - Send

    /// Send a PaCoMessage on the active connection.
    /// Works for both parent (sending commands to child) and child (sending requests to parent).
    func send(message: PaCoMessage) {
        guard let connection = activeConnection else {
            logger.warning("No active connection to send message")
            return
        }
        sendFrame(message: message, on: connection)
    }

    /// Alias for send(message:) — used by child side to send on the parent-opened connection.
    func sendOnActiveConnection(_ message: PaCoMessage) {
        send(message: message)
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

    private func sendFrame(message: PaCoMessage, on connection: NWConnection) {
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

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.logger.info("Accepted incoming connection from parent")
                self?.activeConnection = connection
                // Child starts receive loop to get commands/messages from parent
                self?.receiveChildFrames(on: connection)
            }
        }
        connection.start(queue: .main)
    }

    /// Child-side receive loop: reads PaCoMessage frames sent by parent (e.g. approveExtension).
    private func receiveChildFrames(on connection: NWConnection) {
        receiveOneFrame(on: connection) { [weak self] headerData in
            guard let self else { return }
            let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 1_048_576 else {
                self.logger.warning("Invalid frame length: \(length)")
                return
            }
            let messageLength = Int(length)
            connection.receive(minimumIncompleteLength: messageLength, maximumLength: messageLength) { [weak self] bodyData, _, _, error in
                guard let self else { return }
                if let error { self.logger.error("Child receive body error: \(error)"); return }
                guard let bodyData, bodyData.count == messageLength else { return }
                if let message = try? JSONDecoder().decode(PaCoMessage.self, from: bodyData) {
                    self.logger.info("Child received command: \(message.command.rawValue)")
                    self.onIncomingMessage?(message)
                } else {
                    self.logger.warning("Child could not decode PaCoMessage (\(messageLength) bytes)")
                }
                self.receiveChildFrames(on: connection)
            }
        }
    }

    /// Parent-side receive loop: tries PaCoMessage first (child-initiated), then PaCoResponse (reply).
    private func receiveFrames(
        on connection: NWConnection,
        responseHandler: @escaping (PaCoResponse) -> Void,
        messageHandler: @escaping (PaCoMessage) -> Void
    ) {
        receiveOneFrame(on: connection) { [weak self] headerData in
            guard let self else { return }
            let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 1_048_576 else {
                self.logger.warning("Invalid frame length: \(length)")
                return
            }
            let messageLength = Int(length)
            connection.receive(minimumIncompleteLength: messageLength, maximumLength: messageLength) { [weak self] bodyData, _, _, error in
                guard let self else { return }
                if let error { self.logger.error("Receive body error: \(error)"); return }
                guard let bodyData, bodyData.count == messageLength else { return }
                // Try PaCoMessage first (child-initiated request), then PaCoResponse (reply to our command)
                if let message = try? JSONDecoder().decode(PaCoMessage.self, from: bodyData) {
                    messageHandler(message)
                } else if let response = try? JSONDecoder().decode(PaCoResponse.self, from: bodyData) {
                    responseHandler(response)
                } else {
                    self.logger.warning("Could not decode frame (\(messageLength) bytes)")
                }
                self.receiveFrames(on: connection, responseHandler: responseHandler, messageHandler: messageHandler)
            }
        }
    }

    private func receiveOneFrame(on connection: NWConnection, then handler: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] headerData, _, _, error in
            guard let self else { return }
            if let error {
                self.logger.error("Receive header error (loop stopped): \(error)")
                return
            }
            guard let headerData, headerData.count == 4 else {
                self.logger.warning("Incomplete header received (loop stopped)")
                return
            }
            handler(headerData)
        }
    }
}
