import Foundation
import PaCoShared

/// The daemon's PaCo Cloud client, for a child Mac managed from a browser
/// instead of a parent Mac on the same network.
///
/// It lives in the root daemon because the daemon is always running, owns the
/// policy, and can keep the device token where the monitored user cannot read
/// it (`/Library/Application Support/PaCo/cloud.json`, 0600). Three loops run
/// on one serial queue:
///
/// - **events long-poll**: commands from the parent (policy changes, approvals,
///   manual on/off), turned into actions by `CloudEventReducer`;
/// - **heartbeat** every 30 s: what is enforced right now, and a policy refetch
///   when the server says ours is stale (a missed event);
/// - **usage upload**: the agent's snapshots (`reportUsage`), via `UsageOutbox`.
///
/// While the internet is blocked, the server's addresses stay reachable through
/// a `pf` pass rule (`CloudRelay`), refreshed here by resolving the host.
final class CloudSyncService {

    static let credentialsURL = URL(fileURLWithPath: CloudCredentials.defaultPath)
    static let requestsURL = URL(fileURLWithPath: "/Library/Application Support/PaCo/cloud-requests.json")

    private static let pollWaitSeconds = 25
    private static let pollTimeout: TimeInterval = 40
    private static let requestTimeout: TimeInterval = 20
    private static let pinTimeout: TimeInterval = 10
    private static let heartbeatInterval: TimeInterval = 30
    private static let relayRefreshInterval: TimeInterval = 600
    private static let maxBackoff: TimeInterval = 60
    private static let pendingRequestMaxAge: TimeInterval = 24 * 3600

    /// Plain `http` to a loopback server, for development against
    /// `php artisan serve`. Never in Release.
    private static let allowInsecureLoopback: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private let policyEngine: PolicyEngine
    private let firewall: FirewallManager
    private let logger = PaCoLogger.network
    private let queue = DispatchQueue(label: "com.paco.daemon.cloud")
    private let session: URLSession

    // Everything below is confined to `queue`.
    private var credentials: CloudCredentials?
    private var requests: ChildRequestStore
    private var usage = UsageOutbox()
    private var lastContactAt: Date?
    private var lastError: String?
    /// Bumped whenever the enrollment starts or ends; replies to requests made
    /// under an older generation are dropped.
    private var generation = 0
    private var heartbeatTimer: DispatchSourceTimer?
    private var pollTask: URLSessionDataTask?
    private var pollScheduled = false
    private var backoff: TimeInterval = 1
    private var policyFetchInFlight = false
    private var usageUploadInFlight = false
    private var resolvingRelay = false
    private var rotatingToken = false

    init(policyEngine: PolicyEngine, firewall: FirewallManager) {
        self.policyEngine = policyEngine
        self.firewall = firewall

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.pollTimeout + 5
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "PaCoDaemon/\(PaCoShared.version)",
        ]
        session = URLSession(configuration: configuration)

        var store = ChildRequestStore.load(from: Self.requestsURL)
        store.expirePending(olderThan: Self.pendingRequestMaxAge)
        requests = store
    }

    /// Called once at daemon launch: resume the enrollment, if there is one.
    func start() {
        queue.async { [self] in
            guard let saved = CloudCredentials.load(from: Self.credentialsURL) else { return }
            credentials = saved
            logger.info("PaCo Cloud: enrolled as \(saved.deviceName) at \(saved.serverURL.absoluteString)")
            begin()
        }
    }

    // MARK: - XPC entry points

    func handle(_ request: CloudXPCRequest, reply: @escaping (CloudXPCResponse) -> Void) {
        queue.async { [self] in
            switch request {
            case .status:
                reply(CloudXPCResponse(ok: true, status: status()))
            case let .enroll(serverURL, code, deviceName):
                enroll(serverURL: serverURL, code: code, deviceName: deviceName, reply: reply)
            case .unenroll:
                unenroll(reply: reply)
            case let .submitExtensionRequest(requestId, minutes, reason):
                submitRequest(id: requestId, minutes: minutes, reason: reason, reply: reply)
            case let .withdrawRequest(requestId):
                withdrawRequest(id: requestId, reply: reply)
            case let .verifyPIN(nonce, pin):
                verifyPIN(nonce: nonce, pin: pin, reply: reply)
            }
        }
    }

    /// The agent's usage snapshot. Ignored unless enrolled: nothing is kept for
    /// a Mac that does not report to the cloud.
    func reportUsage(_ data: Data) {
        queue.async { [self] in
            guard credentials != nil,
                  let snapshot = try? JSONDecoder().decode(UsageTransfer.self, from: data) else { return }
            usage.record(snapshot)
            uploadUsageIfDue()
        }
    }

    // MARK: - Lifecycle

    private func begin() {
        generation += 1
        backoff = 1
        if let credentials { firewall.updateRelay(credentials.relay) }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.heartbeat() }
        heartbeatTimer?.cancel()
        heartbeatTimer = timer
        timer.resume()

        pollTask?.cancel()
        pollTask = nil
        pollScheduled = false
        poll()
    }

    private func stop() {
        generation += 1
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        pollTask?.cancel()
        pollTask = nil
        pollScheduled = false
        policyFetchInFlight = false
        usageUploadInFlight = false
    }

    /// Drop the enrollment locally. Enforcement continues with the last policy
    /// the parent sent; only the link to the cloud ends.
    private func forgetEnrollment(reason: String?) {
        stop()
        credentials = nil
        CloudCredentials.delete(at: Self.credentialsURL)
        requests = ChildRequestStore()
        try? FileManager.default.removeItem(at: Self.requestsURL)
        usage = UsageOutbox()
        lastContactAt = nil
        lastError = reason
        firewall.updateRelay(nil)
        logger.warning("PaCo Cloud: enrollment removed\(reason.map { " (\($0))" } ?? "")")
    }

    private func status() -> CloudStatus {
        guard let credentials else {
            var status = CloudStatus.notEnrolled
            status.lastError = lastError
            return status
        }
        let connected = lastContactAt.map { Date().timeIntervalSince($0) < CloudStatus.onlineWindow } ?? false
        return CloudStatus(
            enrolled: true,
            serverURL: credentials.serverURL,
            deviceId: credentials.deviceId,
            deviceName: credentials.deviceName,
            connected: connected,
            lastContactAt: lastContactAt,
            lastError: lastError,
            requests: requests.records)
    }

    // MARK: - Enrollment

    private func enroll(serverURL: String, code: String, deviceName: String, reply: @escaping (CloudXPCResponse) -> Void) {
        guard credentials == nil else {
            reply(.failure("This Mac is already connected to PaCo Cloud.", status: status()))
            return
        }
        guard let base = CloudServerURL.validate(serverURL, allowInsecureLoopback: Self.allowInsecureLoopback),
              let host = base.host else {
            reply(.failure("Enter the PaCo Cloud address, starting with https://."))
            return
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty, !name.isEmpty else {
            reply(.failure("Enter the code shown on the parent's PaCo Cloud page."))
            return
        }

        // If the internet is blocked right now, open the way to this server first.
        let port = base.port ?? (base.scheme == "http" ? 80 : 443)
        Self.resolve(host: host) { [self] addresses in
            queue.async { [self] in
                if !addresses.isEmpty { firewall.updateRelay(CloudRelay(addresses: addresses, port: port)) }

                let body = CloudEnrollRequest(
                    code: trimmedCode, deviceName: name,
                    daemonVersion: PaCoShared.version, timeZone: TimeZone.current.identifier)
                send("POST", "enroll", base: base, authenticated: false, body: try? CloudCodec.encode(body),
                     timeout: Self.requestTimeout) { [self] result in
                    switch result {
                    case .success(let (_, data)):
                        guard let response = try? CloudCodec.decode(CloudEnrollResponse.self, from: data) else {
                            firewall.updateRelay(nil)
                            reply(.failure("The server's answer was not understood. Is this a PaCo Cloud address?"))
                            return
                        }
                        let enrolled = CloudCredentials(
                            serverURL: base, deviceId: response.deviceId, deviceName: response.deviceName,
                            deviceToken: response.deviceToken, eventCursor: response.eventCursor,
                            policyVersion: 0, relayAddresses: addresses,
                            relayResolvedAt: addresses.isEmpty ? nil : Date())
                        do {
                            try enrolled.save(to: Self.credentialsURL)
                        } catch {
                            logger.error("PaCo Cloud: cannot save credentials: \(error.localizedDescription)")
                            firewall.updateRelay(nil)
                            reply(.failure("This Mac could not store its PaCo Cloud enrollment."))
                            return
                        }
                        credentials = enrolled
                        requests = ChildRequestStore()
                        saveRequests()
                        lastError = nil
                        noteContact()
                        logger.info("PaCo Cloud: enrolled as \(enrolled.deviceName) (\(enrolled.deviceId.uuidString))")
                        begin()
                        fetchPolicy()
                        reply(CloudXPCResponse(ok: true, status: status()))

                    case .failure(let error):
                        firewall.updateRelay(nil)
                        reply(.failure(Self.enrollmentMessage(for: error, host: host)))
                    }
                }
            }
        }
    }

    private func unenroll(reply: @escaping (CloudXPCResponse) -> Void) {
        guard credentials != nil else {
            reply(CloudXPCResponse(ok: true, status: status()))
            return
        }
        // Tell the server (best effort) so the parent sees it, then forget locally.
        send("POST", "device/unenroll", timeout: Self.pinTimeout) { [self] _ in
            forgetEnrollment(reason: nil)
            reply(CloudXPCResponse(ok: true, status: status()))
        }
    }

    // MARK: - Time-extension requests

    private func submitRequest(id: UUID, minutes: Int, reason: String, reply: @escaping (CloudXPCResponse) -> Void) {
        guard let credentials else {
            reply(.failure("This Mac is not connected to PaCo Cloud."))
            return
        }
        let payload = ExtensionRequestPayload(
            requestId: id, childDeviceName: credentials.deviceName,
            profileId: policyEngine.policy.activeProfileId,
            requestedMinutes: minutes, reason: reason)
        send("POST", "device/extension-requests", body: try? CloudCodec.encode(payload),
             timeout: Self.requestTimeout) { [self] result in
            switch result {
            case .success:
                noteContact()
                // Recorded only once the server has it: the record is what the
                // approval is matched against and what the child's status card shows.
                requests.record(id: id, requestedMinutes: minutes, reason: reason)
                saveRequests()
                reply(CloudXPCResponse(ok: true, status: status()))
            case .failure(let error):
                handleFailure(error)
                reply(.failure("PaCo Cloud cannot be reached right now. Try again in a moment.", status: status()))
            }
        }
    }

    private func withdrawRequest(id: UUID, reply: @escaping (CloudXPCResponse) -> Void) {
        send("DELETE", "device/extension-requests/\(id.uuidString.lowercased())", timeout: Self.requestTimeout) { [self] result in
            switch result {
            case .success, .failure(.http(status: 404, code: _)):
                requests.withdrawPending()
                saveRequests()
                reply(CloudXPCResponse(ok: true, status: status()))
            case .failure(let error):
                handleFailure(error)
                reply(.failure("PaCo Cloud cannot be reached right now. Try again in a moment.", status: status()))
            }
        }
    }

    private func saveRequests() {
        do {
            try requests.save(to: Self.requestsURL)
        } catch {
            logger.error("PaCo Cloud: cannot save requests: \(error.localizedDescription)")
        }
    }

    // MARK: - Parent Access

    /// The PIN is checked by the server, which holds the hash and the lockout;
    /// this Mac only learns the verdict.
    private func verifyPIN(nonce: UUID, pin: String, reply: @escaping (CloudXPCResponse) -> Void) {
        send("POST", "device/pin/verify", body: try? CloudCodec.encode(PINVerifyRequest(nonce: nonce, pin: pin)),
             timeout: Self.pinTimeout) { [self] result in
            switch result {
            case .success(let (_, data)):
                noteContact()
                guard let verdict = try? CloudCodec.decode(PINVerifyResult.self, from: data), verdict.nonce == nonce else {
                    reply(.failure("PaCo Cloud gave an unexpected answer."))
                    return
                }
                reply(CloudXPCResponse(ok: true, pinResult: verdict))
            case .failure(let error):
                handleFailure(error)
                reply(.failure("PaCo Cloud cannot be reached right now."))
            }
        }
    }

    // MARK: - Events long-poll

    private func poll() {
        guard let credentials, pollTask == nil else { return }
        let gen = generation
        let query = [
            URLQueryItem(name: "cursor", value: String(credentials.eventCursor)),
            URLQueryItem(name: "wait", value: String(Self.pollWaitSeconds)),
        ]
        pollTask = send("GET", "device/events", query: query, timeout: Self.pollTimeout) { [self] result in
            guard gen == generation else { return }
            pollTask = nil
            switch result {
            case .success(let (_, data)):
                guard let response = try? CloudCodec.decode(CloudEventsResponse.self, from: data) else {
                    logger.error("PaCo Cloud: undecodable events response")
                    schedulePoll(after: nextBackoff())
                    return
                }
                noteContact()
                backoff = 1
                apply(response.events)
                schedulePoll(after: response.retryAfter.map(TimeInterval.init) ?? 0)
            case .failure(let error):
                handleFailure(error)
                schedulePoll(after: nextBackoff())
            }
        }
    }

    private func schedulePoll(after delay: TimeInterval) {
        guard credentials != nil, !pollScheduled else { return }
        pollScheduled = true
        let gen = generation
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            guard gen == generation else { return }
            pollScheduled = false
            poll()
        }
    }

    private func nextBackoff() -> TimeInterval {
        let current = backoff
        backoff = min(backoff * 2, Self.maxBackoff)
        return current
    }

    private func apply(_ events: [CloudEvent]) {
        guard let current = credentials, !events.isEmpty else { return }
        var state = CloudSyncState(eventCursor: current.eventCursor, policyVersion: current.policyVersion)
        let actions = CloudEventReducer.reduce(events, state: &state)
        credentials?.eventCursor = state.eventCursor

        for action in actions {
            perform(action)
            if credentials == nil { return }
        }
        saveCredentials()
    }

    private func perform(_ action: CloudAction) {
        do {
            switch action {
            case .fetchPolicy:
                fetchPolicy()
            case .setActiveProfile(let profileId):
                try policyEngine.setActiveProfile(profileId)
            case let .grantOverride(requestId, until):
                try policyEngine.grantOverride(requestId: requestId, until: until)
            case let .resolveRequest(requestId, approved, grantedUntil):
                if requests.resolve(id: requestId, approved: approved, grantedUntil: grantedUntil) {
                    saveRequests()
                }
            case let .setManual(enabled, until):
                try policyEngine.setManual(enabled: enabled, until: until)
            case .clearManual:
                try policyEngine.clearManual()
            case .unenroll:
                forgetEnrollment(reason: "The parent disconnected this Mac from PaCo Cloud.")
            }
            logger.info("PaCo Cloud: applied \(String(describing: action))")
        } catch {
            logger.error("PaCo Cloud: \(String(describing: action)) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Policy

    private func fetchPolicy() {
        guard let credentials, !policyFetchInFlight else { return }
        policyFetchInFlight = true
        let gen = generation
        let headers = credentials.policyVersion > 0 ? ["If-None-Match": "\"v\(credentials.policyVersion)\""] : [:]
        send("GET", "device/policy", headers: headers, timeout: Self.requestTimeout) { [self] result in
            guard gen == generation else { return }
            policyFetchInFlight = false
            switch result {
            case .success(let (http, data)):
                noteContact()
                guard http.statusCode != 304 else { return }
                guard let envelope = try? CloudCodec.decode(CloudPolicyEnvelope.self, from: data) else {
                    logger.error("PaCo Cloud: undecodable policy")
                    return
                }
                applyEnvelope(envelope)
            case .failure(let error):
                handleFailure(error)
            }
        }
    }

    private func applyEnvelope(_ envelope: CloudPolicyEnvelope) {
        do {
            try policyEngine.update(envelope.policy)
            if policyEngine.policy.activeProfileId != envelope.activeProfileId {
                try policyEngine.setActiveProfile(envelope.activeProfileId)
            }
            credentials?.policyVersion = envelope.version
            saveCredentials()
            logger.info("PaCo Cloud: policy v\(envelope.version) applied (\(envelope.policy.schedules.count) schedules, \(envelope.policy.restrictions.count) app rules)")
        } catch {
            logger.error("PaCo Cloud: policy v\(envelope.version) rejected: \(error.localizedDescription)")
        }
    }

    // MARK: - Heartbeat, usage, relay

    private func heartbeat() {
        guard let credentials else { return }
        let gen = generation
        let body = CloudHeartbeatRequest(
            policyVersion: credentials.policyVersion,
            daemonVersion: PaCoShared.version,
            timeZone: TimeZone.current.identifier,
            status: CloudDeviceStatus(policy: policyEngine.policy, internetEnabled: !firewall.isBlocking))
        send("POST", "device/heartbeat", body: try? CloudCodec.encode(body), timeout: Self.requestTimeout) { [self] result in
            guard gen == generation else { return }
            switch result {
            case .success(let (_, data)):
                noteContact()
                let response = try? CloudCodec.decode(CloudHeartbeatResponse.self, from: data)
                if response?.policyStale == true || self.credentials?.policyVersion == 0 {
                    fetchPolicy()
                }
            case .failure(let error):
                handleFailure(error)
            }
        }
        uploadUsageIfDue()
        refreshRelayIfDue()
        rotateTokenIfDue()
        // A poll that died without rescheduling (should not happen) is restarted here.
        if pollTask == nil, !pollScheduled { poll() }
    }

    private func uploadUsageIfDue() {
        guard credentials != nil, !usageUploadInFlight, usage.shouldUpload(now: Date()) else { return }
        let days = usage.pending
        usageUploadInFlight = true
        let gen = generation
        let body = CloudUsageUpload(timeZone: TimeZone.current.identifier, days: days)
        send("POST", "device/usage", body: try? CloudCodec.encode(body), timeout: Self.requestTimeout) { [self] result in
            guard gen == generation else { return }
            usageUploadInFlight = false
            switch result {
            case .success:
                noteContact()
                usage.markUploaded(days, at: Date())
            case .failure(let error):
                usage.markFailed(at: Date())
                handleFailure(error)
            }
        }
    }

    /// Keep the `pf` pass rule pointing at the server's current addresses. The
    /// last known addresses are kept when resolution fails (DNS may be blocked).
    private func refreshRelayIfDue() {
        guard let credentials, !resolvingRelay, let host = credentials.serverURL.host else { return }
        let due = credentials.relayAddresses.isEmpty
            || (credentials.relayResolvedAt.map { Date().timeIntervalSince($0) > Self.relayRefreshInterval } ?? true)
        guard due else { return }
        resolvingRelay = true
        let gen = generation
        Self.resolve(host: host) { [self] addresses in
            queue.async { [self] in
                resolvingRelay = false
                guard gen == generation, var updated = self.credentials, !addresses.isEmpty else { return }
                updated.relayResolvedAt = Date()
                if Set(addresses) != Set(updated.relayAddresses) {
                    updated.relayAddresses = addresses
                    firewall.updateRelay(updated.relay)
                }
                self.credentials = updated
                saveCredentials()
            }
        }
    }

    /// Every 30 days. Crash-safe: the server accepts the old token until the new
    /// one is used, and the new one is used only after it was saved here.
    private func rotateTokenIfDue() {
        guard let credentials, !rotatingToken, credentials.needsTokenRotation() else { return }
        rotatingToken = true
        let gen = generation
        send("POST", "device/token/rotate", timeout: Self.requestTimeout) { [self] result in
            guard gen == generation else { return }
            rotatingToken = false
            switch result {
            case .success(let (_, data)):
                guard let rotation = try? CloudCodec.decode(CloudTokenRotation.self, from: data),
                      var updated = self.credentials else { return }
                updated.deviceToken = rotation.deviceToken
                updated.tokenIssuedAt = rotation.rotatedAt
                do {
                    try updated.save(to: Self.credentialsURL)
                    self.credentials = updated
                    logger.info("PaCo Cloud: device token rotated")
                } catch {
                    logger.error("PaCo Cloud: rotated token not saved, keeping the old one: \(error.localizedDescription)")
                }
            case .failure(let error):
                handleFailure(error)
            }
        }
    }

    private func saveCredentials() {
        guard let credentials else { return }
        do {
            try credentials.save(to: Self.credentialsURL)
        } catch {
            logger.error("PaCo Cloud: cannot save credentials: \(error.localizedDescription)")
        }
    }

    private func noteContact() {
        lastContactAt = Date()
        lastError = nil
    }

    private func handleFailure(_ error: CloudHTTPError) {
        switch error {
        case .http(status: 401, code: CloudErrorBody.deviceRevoked):
            forgetEnrollment(reason: "The parent disconnected this Mac from PaCo Cloud.")
        case .http(status: 401, code: _):
            lastError = "PaCo Cloud no longer accepts this Mac. Ask the parent to enroll it again."
        case .http(let status, _):
            lastError = "PaCo Cloud answered with an error (\(status))."
        case .transport(let message):
            lastError = "PaCo Cloud cannot be reached (\(message))."
        case .invalidResponse:
            lastError = "PaCo Cloud gave an unexpected answer."
        }
        logger.warning("PaCo Cloud: \(self.lastError ?? String(describing: error))")
    }

    private static func enrollmentMessage(for error: CloudHTTPError, host: String) -> String {
        switch error {
        case .http(status: 410, _), .http(status: 422, _):
            return "That code is not valid or has expired. Ask the parent for a new one."
        case .http(status: 429, _):
            return "Too many attempts. Wait a minute and try again."
        case .http(let status, _):
            return "\(host) answered with an error (\(status)). Is this a PaCo Cloud address?"
        case .transport:
            return "Cannot reach \(host). Check the address and the network connection."
        case .invalidResponse:
            return "The server's answer was not understood. Is this a PaCo Cloud address?"
        }
    }

    // MARK: - HTTP

    enum CloudHTTPError: Error {
        case transport(String)
        case http(status: Int, code: String?)
        case invalidResponse
    }

    /// Send a request to the device API; the completion runs on `queue`.
    /// `base` defaults to the enrolled server; `authenticated` sends the device token.
    @discardableResult
    private func send(
        _ method: String,
        _ path: String,
        base: URL? = nil,
        authenticated: Bool = true,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval,
        completion: @escaping (Result<(HTTPURLResponse, Data), CloudHTTPError>) -> Void
    ) -> URLSessionDataTask? {
        guard let serverURL = base ?? credentials?.serverURL else {
            completion(.failure(.transport("not enrolled")))
            return nil
        }
        var url = CloudServerURL.endpoint(serverURL, path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        if authenticated, let bearer = credentials?.deviceToken { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let result: Result<(HTTPURLResponse, Data), CloudHTTPError>
            if let error {
                result = .failure(.transport((error as NSError).localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                let data = data ?? Data()
                if (200..<300).contains(http.statusCode) || http.statusCode == 304 {
                    result = .success((http, data))
                } else {
                    let code = (try? CloudCodec.decode(CloudErrorBody.self, from: data))?.error
                    result = .failure(.http(status: http.statusCode, code: code))
                }
            } else {
                result = .failure(.invalidResponse)
            }
            self.queue.async { completion(result) }
        }
        task.resume()
        return task
    }

    // MARK: - DNS

    /// Resolve `host` to literal addresses off the queue (getaddrinfo blocks).
    static func resolve(host: String, completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if FirewallRuleBuilder.isIPAddress(bare) {
                completion([bare])
                return
            }
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var list: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(bare, nil, &hints, &list) == 0, let first = list else {
                completion([])
                return
            }
            defer { freeaddrinfo(list) }

            var addresses: [String] = []
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let info = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: buffer)
                    if FirewallRuleBuilder.isIPAddress(address), !addresses.contains(address) {
                        addresses.append(address)
                    }
                }
                cursor = info.pointee.ai_next
            }
            completion(addresses)
        }
    }
}
