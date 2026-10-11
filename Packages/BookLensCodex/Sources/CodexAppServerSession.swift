import BookLensDomain
import BookLensSupport
import Foundation

actor CodexRateLimitCache {
    private struct Entry: Codable {
        let snapshot: CodexRateLimitSnapshot
        let cachedAt: Date
    }

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let maximumAge: TimeInterval

    init(
        defaultsSuiteName: String? = nil,
        defaultsKey: String = "BookLens.Codex.lastRateLimitSnapshot",
        maximumAge: TimeInterval = 24 * 60 * 60
    ) {
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaultsKey = defaultsKey
        self.maximumAge = maximumAge
    }

    func record(_ snapshot: CodexRateLimitSnapshot, now: Date = .now) -> CodexRateLimitSnapshot {
        let entry = Entry(snapshot: snapshot, cachedAt: now)
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: defaultsKey)
        }
        return snapshot
    }

    func latest(now: Date = .now) -> CodexRateLimitSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              now.timeIntervalSince(entry.cachedAt) <= maximumAge,
              entry.snapshot.resetsAt.map({ $0 > now }) ?? true
        else {
            defaults.removeObject(forKey: defaultsKey)
            return nil
        }
        return entry.snapshot
    }
}

private let codexRateLimitCache = CodexRateLimitCache()

public struct CodexHandshake: Equatable, Sendable {
    public let userAgent: String
    public let platformFamily: String
    public let platformOS: String

    public init(userAgent: String, platformFamily: String, platformOS: String) {
        self.userAgent = userAgent
        self.platformFamily = platformFamily
        self.platformOS = platformOS
    }
}

public struct CodexLoginChallenge: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case browser(url: URL)
        case deviceCode(url: URL, code: String)
    }

    public let loginID: String
    public let kind: Kind

    public init(loginID: String, kind: Kind) {
        self.loginID = loginID
        self.kind = kind
    }
}

public actor CodexAppServerSession: CodexAccountServicing {
    private let installation: CodexInstallation
    private let client: JSONRPCClient
    private var didInitialize = false

    public init(installation: CodexInstallation) {
        self.installation = installation
        let transport = CodexProcessController(executableURL: installation.executableURL)
        client = JSONRPCClient(transport: transport)
    }

    public nonisolated func notifications() -> AsyncStream<JSONRPCNotification> {
        client.notifications()
    }

    public func start() async throws -> CodexHandshake {
        guard installation.compatibility == .compatible else {
            throw BookLensError.incompatibleCodexVersion(
                found: installation.version,
                supported: CodexExecutableResolver.supportedVersionDescription
            )
        }
        try await client.start()
        let response = try await client.request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "BookLens",
                    "title": "BookLens",
                    "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"),
                ],
                "capabilities": ["experimentalApi": true],
            ],
            timeout: .seconds(10)
        )
        guard let userAgent = response["userAgent"]?.stringValue,
              let family = response["platformFamily"]?.stringValue,
              let os = response["platformOs"]?.stringValue
        else {
            throw BookLensError.handshakeFailed
        }
        try await client.notify(method: "initialized")
        didInitialize = true
        return CodexHandshake(userAgent: userAgent, platformFamily: family, platformOS: os)
    }

    public func readAccount() async throws -> CodexAccountSnapshot {
        try requireInitialized()
        let accountResponse = try await client.request(
            method: "account/read",
            params: ["refreshToken": false]
        )
        let account = accountResponse["account"]?.objectValue
        let requiresAuth = accountResponse["requiresOpenaiAuth"]?.boolValue ?? true

        var liveRateLimit: CodexRateLimitSnapshot?
        do {
            let limits = try await client.request(method: "account/rateLimits/read")
            liveRateLimit = CodexRateLimitParser().parsePrimary(from: limits)
        } catch {
            liveRateLimit = nil
        }
        let rateLimit = if let liveRateLimit {
            await codexRateLimitCache.record(liveRateLimit)
        } else {
            await codexRateLimitCache.latest()
        }

        return CodexAccountSnapshot(
            requiresOpenAIAuth: requiresAuth,
            accountType: account?["type"]?.stringValue,
            planType: account?["planType"]?.stringValue,
            hasRateLimitSnapshot: liveRateLimit != nil,
            primaryRateLimit: rateLimit
        )
    }

    public func beginBrowserLogin() async throws -> CodexLoginChallenge {
        try requireInitialized()
        let response = try await client.request(
            method: "account/login/start",
            params: [
                "type": "chatgpt",
                "appBrand": "codex",
                "codexStreamlinedLogin": true,
                "useHostedLoginSuccessPage": true,
            ],
            timeout: .seconds(30)
        )
        guard let loginID = response["loginId"]?.stringValue,
              let urlString = response["authUrl"]?.stringValue,
              let parsedURL = URL(string: urlString)
        else {
            throw BookLensError.protocolViolation(code: "login-browser-shape")
        }
        let url = try Self.validateAuthenticationURL(parsedURL)
        return CodexLoginChallenge(loginID: loginID, kind: .browser(url: url))
    }

    public func beginDeviceCodeLogin() async throws -> CodexLoginChallenge {
        try requireInitialized()
        let response = try await client.request(
            method: "account/login/start",
            params: ["type": "chatgptDeviceCode"],
            timeout: .seconds(30)
        )
        guard let loginID = response["loginId"]?.stringValue,
              let urlString = response["verificationUrl"]?.stringValue,
              let parsedURL = URL(string: urlString),
              let code = response["userCode"]?.stringValue
        else {
            throw BookLensError.protocolViolation(code: "login-device-shape")
        }
        let url = try Self.validateAuthenticationURL(parsedURL)
        return CodexLoginChallenge(loginID: loginID, kind: .deviceCode(url: url, code: code))
    }

    nonisolated static func validateAuthenticationURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              host == "openai.com"
                || host.hasSuffix(".openai.com")
                || host == "chatgpt.com"
                || host.hasSuffix(".chatgpt.com")
        else {
            throw BookLensError.protocolViolation(code: "untrusted-auth-url")
        }
        return url
    }

    public func listModels() async throws -> [CodexModelOption] {
        try requireInitialized()
        return try await CodexModelCatalog().load(using: client)
    }

    public func request(method: String, params: JSONValue? = nil, timeout: Duration? = nil) async throws -> JSONValue {
        try requireInitialized()
        return try await client.request(method: method, params: params, timeout: timeout)
    }

    public func interrupt(threadID: String, turnID: String) async throws {
        _ = try await request(
            method: "turn/interrupt",
            params: ["threadId": .string(threadID), "turnId": .string(turnID)]
        )
    }

    public func stop() async {
        didInitialize = false
        await client.stop()
    }

    private func requireInitialized() throws {
        guard didInitialize else {
            throw BookLensError.handshakeFailed
        }
    }
}
