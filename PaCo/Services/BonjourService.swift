import Foundation
import Network
import Security
import PaCoShared

/// Manages Bonjour discovery and TLS-PSK-secured communication between parent and child devices.
///
/// Trust model: the parent↔child channel is encrypted and authenticated with a
/// pre-shared key derived from a one-time pairing code (see `PairingKeyManager`).
/// An unpaired peer has no matching key and fails the TLS handshake, so it cannot
/// send commands or requests.
///
/// Roles: the **child** advertises an `NWListener` (TLS server); the **parent**
/// browses and opens one `NWConnection` per paired child (TLS client).
final class BonjourService: ObservableObject {

    @Published var discoveredDevices: [NWBrowser.Result] = []
    @Published var isListening = false

    private var browser: NWBrowser?
    private var listener: NWListener?

    /// Child side: the single accepted connection from the parent.
    private var childConnection: NWConnection?
    /// Parent side: one connection per paired child, keyed by child identity (device name).
    private var parentConnections: [String: NWConnection] = [:]

    private let logger = PaCoLogger.network

    /// Child side: inbound command from the parent (e.g. approveExtension, provisionPIN).
    var onIncomingMessage: ((PaCoMessage) -> Void)?
    /// Parent side: inbound request from a child, with the child's identity.
    var onChildRequest: ((PaCoMessage, String) -> Void)?
    /// Parent side: a connection to a child just became ready (identity).
    var onParentConnected: ((String) -> Void)?

    private let serviceType = "_paco._tcp"
    private let serviceDomain = "local."
    /// TLS-PSK identity label (sent in the clear; key selection is done by the app).
    private static let pskIdentity = Data("com.paco".utf8)
    /// Deterministic key used only so an unpaired child is still discoverable by name.
    private static let unpairedBootstrapCode = "PACO-UNPAIRED-BOOTSTRAP"

    // MARK: - TLS-PSK parameters

    private func tlsParameters(psk: Data) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions

        psk.withUnsafeBytes { (pskPtr: UnsafeRawBufferPointer) in
            Self.pskIdentity.withUnsafeBytes { (idPtr: UnsafeRawBufferPointer) in
                let pskDD = DispatchData(bytes: pskPtr)
                let idDD = DispatchData(bytes: idPtr)
                sec_protocol_options_add_pre_shared_key(
                    secOptions, pskDD as __DispatchData, idDD as __DispatchData
                )
            }
        }
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)
        if let suite = tls_ciphersuite_t(rawValue: 0x00A8) {  // TLS_PSK_WITH_AES_128_GCM_SHA256
            sec_protocol_options_append_tls_ciphersuite(secOptions, suite)
        }

        let params = NWParameters(tls: tlsOptions)
        params.includePeerToPeer = true
        return params
    }

    /// The child's PSK: its paired parent's key, or a bootstrap key (discoverable but unconnectable) if unpaired.
    private func childPSK() -> Data {
        if let key = PairingKeyManager.allKeys().first?.key { return key }
        return (try? PairingKeyManager.deriveKey(fromCode: Self.unpairedBootstrapCode)) ?? Data(count: 32)
    }

    // MARK: - Advertise (child mode)

    func startAdvertising(name: String) {
        listener?.cancel()
        do {
            let listener = try NWListener(using: tlsParameters(psk: childPSK()))
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

    /// Restart the child listener after pairing so the real PSK takes effect.
    func restartAdvertising(name: String) {
        startAdvertising(name: name)
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

    // MARK: - Connect (parent to a specific paired child)

    /// Connect to a paired child endpoint. Requires a stored pairing key for `identity`.
    func connect(
        to endpoint: NWEndpoint,
        identity: String,
        responseHandler: @escaping (PaCoResponse) -> Void,
        incomingMessageHandler: @escaping (PaCoMessage) -> Void
    ) {
        guard let psk = PairingKeyManager.key(for: identity) else {
            logger.warning("Refusing to connect to '\(identity)': no pairing key (not paired)")
            return
        }
        let connection = NWConnection(to: endpoint, using: tlsParameters(psk: psk))

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Connected (TLS) to child '\(identity)'")
                self?.receiveParentFrames(on: connection, identity: identity,
                                          responseHandler: responseHandler,
                                          messageHandler: incomingMessageHandler)
                self?.onParentConnected?(identity)
            case .failed(let error):
                self?.logger.error("Connection to '\(identity)' failed: \(error)")
                DispatchQueue.main.async { self?.parentConnections[identity] = nil }
            case .cancelled:
                DispatchQueue.main.async { self?.parentConnections[identity] = nil }
            default:
                break
            }
        }

        connection.start(queue: .main)
        parentConnections[identity] = connection
    }

    func isConnected(to identity: String) -> Bool {
        parentConnections[identity] != nil
    }

    // MARK: - Send

    /// Parent → a specific child.
    func send(_ message: PaCoMessage, to identity: String) {
        guard let connection = parentConnections[identity] else {
            logger.warning("No active connection to '\(identity)' to send \(message.command.rawValue)")
            return
        }
        sendFrame(message: message, on: connection)
    }

    /// Child → parent, on the accepted connection.
    func sendToParent(_ message: PaCoMessage) {
        guard let connection = childConnection else {
            logger.warning("No active parent connection to send message")
            return
        }
        sendFrame(message: message, on: connection)
    }

    // MARK: - Stop

    func stop() {
        browser?.cancel()
        listener?.cancel()
        childConnection?.cancel()
        parentConnections.values.forEach { $0.cancel() }
        browser = nil
        listener = nil
        childConnection = nil
        parentConnections = [:]
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
                self?.logger.info("Accepted incoming TLS connection from parent")
                self?.childConnection = connection
                self?.receiveChildFrames(on: connection)
            }
        }
        connection.start(queue: .main)
    }

    /// Child-side receive loop: PaCoMessage frames sent by the parent.
    private func receiveChildFrames(on connection: NWConnection) {
        receiveOneFrame(on: connection) { [weak self] headerData in
            guard let self else { return }
            guard let messageLength = self.frameBodyLength(headerData) else { return }
            connection.receive(minimumIncompleteLength: messageLength, maximumLength: messageLength) { [weak self] bodyData, _, _, error in
                guard let self else { return }
                if let error { self.logger.error("Child receive body error: \(error)"); return }
                guard let bodyData, bodyData.count == messageLength else { return }
                let (type, json) = self.splitFrameBody(bodyData)
                if type == .message, let message = try? JSONDecoder().decode(PaCoMessage.self, from: json) {
                    self.logger.info("Child received command: \(message.command.rawValue)")
                    self.onIncomingMessage?(message)
                } else {
                    self.logger.warning("Child could not decode frame (\(messageLength) bytes)")
                }
                self.receiveChildFrames(on: connection)
            }
        }
    }

    /// Parent-side receive loop for one child connection: child-initiated requests + replies.
    private func receiveParentFrames(
        on connection: NWConnection,
        identity: String,
        responseHandler: @escaping (PaCoResponse) -> Void,
        messageHandler: @escaping (PaCoMessage) -> Void
    ) {
        receiveOneFrame(on: connection) { [weak self] headerData in
            guard let self else { return }
            guard let messageLength = self.frameBodyLength(headerData) else { return }
            connection.receive(minimumIncompleteLength: messageLength, maximumLength: messageLength) { [weak self] bodyData, _, _, error in
                guard let self else { return }
                if let error { self.logger.error("Receive body error: \(error)"); return }
                guard let bodyData, bodyData.count == messageLength else { return }
                let (type, json) = self.splitFrameBody(bodyData)
                switch type {
                case .message:
                    if let message = try? JSONDecoder().decode(PaCoMessage.self, from: json) {
                        messageHandler(message)
                        self.onChildRequest?(message, identity)
                    }
                case .response:
                    if let response = try? JSONDecoder().decode(PaCoResponse.self, from: json) {
                        responseHandler(response)
                    }
                case .none:
                    self.logger.warning("Could not decode frame (\(messageLength) bytes)")
                }
                self.receiveParentFrames(on: connection, identity: identity,
                                         responseHandler: responseHandler, messageHandler: messageHandler)
            }
        }
    }

    /// Split a frame body into its type byte and JSON payload.
    private func splitFrameBody(_ body: Data) -> (FrameType?, Data) {
        guard let first = body.first else { return (nil, Data()) }
        return (FrameType(rawValue: first), Data(body.dropFirst()))
    }

    /// Parse and validate the 4-byte big-endian length header; nil if invalid.
    private func frameBodyLength(_ headerData: Data) -> Int? {
        let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length > 0, length < 1_048_576 else {
            logger.warning("Invalid frame length: \(length)")
            return nil
        }
        return Int(length)
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
