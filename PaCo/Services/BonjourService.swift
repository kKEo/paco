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
/// browses and keeps one `NWConnection` per paired child (TLS client). Connecting
/// is automatic and app-level: whenever a discovered service has a stored pairing
/// key and no live connection, the parent connects (on browse changes and on a
/// periodic retry), so child requests and policy pushes work without the Devices
/// tab being open.
final class BonjourService: ObservableObject {

    @Published private(set) var discoveredDevices: [NWBrowser.Result] = []
    @Published private(set) var isListening = false
    /// Parent side: identities whose connection is ready (TLS handshake done).
    @Published private(set) var connectedIdentities: Set<String> = []
    /// Child side: a parent connection is currently ready.
    @Published private(set) var isParentConnected = false

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var retryTimer: DispatchSourceTimer?

    /// Child side: the single accepted connection from the parent.
    private var childConnection: NWConnection?
    /// Parent side: one connection per paired child (in progress or ready), keyed by identity.
    private var parentConnections: [String: NWConnection] = [:]
    /// Parent side: pending give-up timers for connections stuck before `.ready`.
    private var connectTimeouts: [String: DispatchWorkItem] = [:]

    private let logger = PaCoLogger.network

    /// Child side: inbound command from the parent (e.g. approveExtension, updatePolicy).
    var onIncomingMessage: ((PaCoMessage) -> Void)?
    /// Child side: the parent's reply to a request we sent (e.g. verifyPIN).
    var onIncomingResponse: ((PaCoResponse) -> Void)?
    /// Parent side: inbound request from a child, with the identity it arrived on.
    var onChildRequest: ((PaCoMessage, String) -> Void)?
    /// Parent side: a reply from a child to a command we sent.
    var onChildResponse: ((PaCoResponse, String) -> Void)?
    /// Parent side: a connection to a child just became ready (identity).
    var onParentConnected: ((String) -> Void)?

    private let serviceType = "_paco._tcp"
    private let serviceDomain = "local."
    /// TLS-PSK identity label (sent in the clear; key selection is done by the app).
    private static let pskIdentity = Data("com.paco".utf8)
    /// How long a parent→child connection may sit in `.preparing`/`.waiting` before we give up and retry later.
    private static let connectTimeout: TimeInterval = 20
    private static let retryInterval: TimeInterval = 30

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

    // MARK: - Advertise (child mode)

    /// Advertise this child. Paired: a TLS-PSK listener keyed with the parent's
    /// key. Unpaired: a plain listener that exists only so the parent can see the
    /// name in "Nearby Devices"; every connection to it is dropped immediately, so
    /// nothing on the LAN can send commands to an unpaired child.
    func startAdvertising(name: String) {
        listener?.cancel()
        let pairedKey = PairingKeyManager.allKeys().first?.key
        do {
            let listener = try NWListener(using: pairedKey.map(tlsParameters(psk:)) ?? .tcp)
            listener.service = NWListener.Service(name: name, type: serviceType, domain: serviceDomain)

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logger.info("Bonjour: advertising as '\(name)'")
                    self?.isListening = true
                case .failed(let error):
                    self?.logger.error("Bonjour listener failed: \(error)")
                    self?.isListening = false
                case .cancelled:
                    self?.isListening = false
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard pairedKey != nil else {
                    self?.logger.warning("Dropping connection: this child is not paired")
                    connection.cancel()
                    return
                }
                self?.handleIncomingConnection(connection)
            }

            listener.start(queue: .main)
            self.listener = listener
            if pairedKey == nil {
                logger.info("Bonjour: advertising unpaired (discovery only, connections refused)")
            }
        } catch {
            logger.error("Failed to start Bonjour listener: \(error)")
        }
    }

    /// Restart the child listener after pairing so the real PSK takes effect.
    func restartAdvertising(name: String) {
        startAdvertising(name: name)
    }

    // MARK: - Browse + auto-connect (parent mode)

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: .tcp)

        browser.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.logger.info("Bonjour: browsing for devices")
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.discoveredDevices = Array(results)
            self.autoConnectPairedDevices()
        }

        browser.start(queue: .main)
        self.browser = browser

        // A child that restarts its listener, or a connection that died quietly,
        // is picked up here even if the browse results did not change.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.retryInterval, repeating: Self.retryInterval)
        timer.setEventHandler { [weak self] in self?.autoConnectPairedDevices() }
        timer.resume()
        retryTimer = timer
    }

    /// Connect to every discovered service that has a stored pairing key and no
    /// live or in-progress connection. Safe to call often.
    func autoConnectPairedDevices() {
        for result in discoveredDevices {
            let identity = Self.serviceName(of: result)
            guard parentConnections[identity] == nil,
                  PairingKeyManager.key(for: identity) != nil else { continue }
            connect(to: result.endpoint, identity: identity)
        }
    }

    /// Open (or re-open) a connection to a paired child. Requires a stored pairing key for `identity`.
    func connect(to endpoint: NWEndpoint, identity: String) {
        guard let psk = PairingKeyManager.key(for: identity) else {
            logger.warning("Refusing to connect to '\(identity)': no pairing key (not paired)")
            return
        }
        if let existing = parentConnections[identity] {
            existing.cancel()
        }
        let connection = NWConnection(to: endpoint, using: tlsParameters(psk: psk))
        parentConnections[identity] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.parentConnections[identity] === connection else { return }
            switch state {
            case .preparing:
                self.armConnectTimeout(for: identity)
            case .waiting(let error):
                // Typically "no route" / child not reachable yet. NWConnection keeps
                // trying on its own; the timeout below bounds how long we let it.
                self.logger.warning("Connection to '\(identity)' waiting: \(error)")
                self.armConnectTimeout(for: identity)
            case .ready:
                self.cancelConnectTimeout(for: identity)
                self.logger.info("Connected (TLS) to child '\(identity)'")
                self.connectedIdentities.insert(identity)
                self.receiveParentFrames(on: connection, identity: identity)
                self.onParentConnected?(identity)
            case .failed(let error):
                self.logger.error("Connection to '\(identity)' failed: \(error)")
                self.forgetParentConnection(identity)
            case .cancelled:
                self.forgetParentConnection(identity)
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    /// Drop the connection to a child (e.g. after its pairing was removed).
    func disconnect(identity: String) {
        parentConnections[identity]?.cancel()
        forgetParentConnection(identity)
    }

    /// True while the TLS connection to `identity` is ready to carry messages.
    func isConnected(to identity: String) -> Bool {
        connectedIdentities.contains(identity)
    }

    private func armConnectTimeout(for identity: String) {
        guard connectTimeouts[identity] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.connectedIdentities.contains(identity) else { return }
            self.logger.warning("Giving up on connection to '\(identity)' after \(Int(Self.connectTimeout))s; will retry")
            self.disconnect(identity: identity)
        }
        connectTimeouts[identity] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout, execute: work)
    }

    private func cancelConnectTimeout(for identity: String) {
        connectTimeouts[identity]?.cancel()
        connectTimeouts[identity] = nil
    }

    private func forgetParentConnection(_ identity: String) {
        cancelConnectTimeout(for: identity)
        parentConnections[identity] = nil
        connectedIdentities.remove(identity)
    }

    /// The advertised service name of a browse result (the child's identity).
    static func serviceName(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return result.endpoint.debugDescription
    }

    // MARK: - Send

    /// Parent → a specific child. Returns false if there is no ready connection.
    @discardableResult
    func send(_ message: PaCoMessage, to identity: String) -> Bool {
        guard connectedIdentities.contains(identity), let connection = parentConnections[identity] else {
            logger.warning("No active connection to '\(identity)' to send \(message.command.rawValue)")
            return false
        }
        return sendFrame(try? message.encoded(), on: connection)
    }

    /// Child → parent, on the accepted connection. Returns false if the parent is not connected.
    @discardableResult
    func sendToParent(_ message: PaCoMessage) -> Bool {
        guard isParentConnected, let connection = childConnection else {
            logger.warning("No active parent connection to send \(message.command.rawValue)")
            return false
        }
        return sendFrame(try? message.encoded(), on: connection)
    }

    /// Child → parent reply to a command.
    @discardableResult
    func replyToParent(_ response: PaCoResponse) -> Bool {
        guard isParentConnected, let connection = childConnection else { return false }
        return sendFrame(try? response.encoded(), on: connection)
    }

    /// Parent → child reply to a child's request.
    @discardableResult
    func reply(_ response: PaCoResponse, to identity: String) -> Bool {
        guard connectedIdentities.contains(identity), let connection = parentConnections[identity] else { return false }
        return sendFrame(try? response.encoded(), on: connection)
    }

    // MARK: - Stop

    func stop() {
        browser?.cancel()
        listener?.cancel()
        retryTimer?.cancel()
        childConnection?.cancel()
        parentConnections.values.forEach { $0.cancel() }
        connectTimeouts.values.forEach { $0.cancel() }
        browser = nil
        listener = nil
        retryTimer = nil
        childConnection = nil
        parentConnections = [:]
        connectTimeouts = [:]
        connectedIdentities = []
        isParentConnected = false
        discoveredDevices = []
        isListening = false
    }

    // MARK: - Private

    private func sendFrame(_ data: Data?, on connection: NWConnection) -> Bool {
        guard let data else {
            logger.error("Message encoding failed")
            return false
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Send failed: \(error)")
            }
        })
        return true
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("Accepted incoming TLS connection from parent")
                if let previous = self.childConnection, previous !== connection {
                    previous.cancel()
                }
                self.childConnection = connection
                self.isParentConnected = true
                self.receiveChildFrames(on: connection)
            case .failed(let error):
                self.logger.warning("Parent connection failed: \(error)")
                self.forgetChildConnection(connection)
            case .cancelled:
                self.forgetChildConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func forgetChildConnection(_ connection: NWConnection) {
        guard childConnection === connection else { return }
        childConnection = nil
        isParentConnected = false
        logger.info("Parent disconnected")
    }

    /// Child-side receive loop: commands and replies sent by the parent.
    private func receiveChildFrames(on connection: NWConnection) {
        receiveFrame(on: connection) { [weak self] type, json in
            guard let self else { return }
            switch type {
            case .message:
                if let message = try? JSONDecoder().decode(PaCoMessage.self, from: json) {
                    self.logger.info("Child received command: \(message.command.rawValue)")
                    self.onIncomingMessage?(message)
                }
            case .response:
                if let response = try? JSONDecoder().decode(PaCoResponse.self, from: json) {
                    self.onIncomingResponse?(response)
                }
            case .none:
                self.logger.warning("Child could not decode frame (\(json.count) bytes)")
            }
            self.receiveChildFrames(on: connection)
        }
    }

    /// Parent-side receive loop for one child connection: child-initiated requests + replies.
    private func receiveParentFrames(on connection: NWConnection, identity: String) {
        receiveFrame(on: connection) { [weak self] type, json in
            guard let self else { return }
            switch type {
            case .message:
                if let message = try? JSONDecoder().decode(PaCoMessage.self, from: json) {
                    self.onChildRequest?(message, identity)
                }
            case .response:
                if let response = try? JSONDecoder().decode(PaCoResponse.self, from: json) {
                    self.onChildResponse?(response, identity)
                }
            case .none:
                self.logger.warning("Could not decode frame from '\(identity)' (\(json.count) bytes)")
            }
            self.receiveParentFrames(on: connection, identity: identity)
        }
    }

    /// Receive one length-prefixed frame and hand back its type byte and JSON body.
    /// Any receive error cancels the connection so the state handler cleans up
    /// and (on the parent) the retry path reconnects.
    private func receiveFrame(on connection: NWConnection, then handler: @escaping (FrameType?, Data) -> Void) {
        connection.receive(minimumIncompleteLength: FrameCodec.headerLength, maximumLength: FrameCodec.headerLength) { [weak self] headerData, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.logger.error("Receive header error: \(error)")
                connection.cancel()
                return
            }
            guard let headerData, headerData.count == FrameCodec.headerLength else {
                if isComplete { self.logger.info("Peer closed the connection") }
                else { self.logger.warning("Incomplete header received") }
                connection.cancel()
                return
            }
            guard let length = FrameCodec.bodyLength(header: headerData) else {
                self.logger.warning("Invalid frame header")
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] bodyData, _, _, error in
                guard let self else { return }
                if let error {
                    self.logger.error("Receive body error: \(error)")
                    connection.cancel()
                    return
                }
                guard let bodyData, bodyData.count == length, let body = FrameCodec.decodeBody(bodyData) else {
                    connection.cancel()
                    return
                }
                handler(body.type, body.json)
            }
        }
    }

}
