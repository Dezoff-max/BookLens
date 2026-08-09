import Foundation

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public var limitID: String?
    public var limitName: String?
    public var usedPercent: Int
    public var windowDurationMinutes: Int?
    public var resetsAt: Date?

    public init(
        limitID: String?,
        limitName: String?,
        usedPercent: Int,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        100 - usedPercent
    }
}

public struct CodexAccountSnapshot: Codable, Equatable, Sendable {
    public var requiresOpenAIAuth: Bool
    public var accountType: String?
    public var planType: String?
    public var hasRateLimitSnapshot: Bool
    public var primaryRateLimit: CodexRateLimitSnapshot?

    public init(
        requiresOpenAIAuth: Bool,
        accountType: String?,
        planType: String?,
        hasRateLimitSnapshot: Bool,
        primaryRateLimit: CodexRateLimitSnapshot? = nil
    ) {
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.accountType = accountType
        self.planType = planType
        self.hasRateLimitSnapshot = hasRateLimitSnapshot
        self.primaryRateLimit = primaryRateLimit
    }
}

public protocol CodexAccountServicing: Sendable {
    func readAccount() async throws -> CodexAccountSnapshot
}

public protocol CodexSessionServicing: Sendable {
    func startSession(in workingDirectory: URL) async throws -> String
    func interrupt(threadID: String, turnID: String) async throws
}

public protocol CodexGenerationServicing: Sendable {
    func generate(
        job: GenerationJob,
        profile: CharacterProfileSnapshot,
        settings: GenerationSettings,
        references: [GenerationReference]
    ) async throws -> Artwork
}
