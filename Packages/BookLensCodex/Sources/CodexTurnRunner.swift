import BookLensSupport
import Foundation

public struct CodexTurnHandle: Equatable, Sendable {
    public let threadID: String
    public let turnID: String

    public init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

public struct CodexTurnOutcome: Equatable, Sendable {
    public let status: String
    public let finalMessage: String?
    public let errorType: String?

    public init(status: String, finalMessage: String?, errorType: String?) {
        self.status = status
        self.finalMessage = finalMessage
        self.errorType = errorType
    }
}

public struct CodexTurnProgress: Equatable, Sendable {
    public let method: String
    public let itemType: String?
    public let status: String?

    public init(method: String, itemType: String? = nil, status: String? = nil) {
        self.method = method
        self.itemType = itemType
        self.status = status
    }
}

public typealias CodexTurnProgressHandler = @Sendable (CodexTurnProgress) async -> Void

public actor CodexTurnRunner {
    private let session: CodexAppServerSession

    public init(session: CodexAppServerSession) {
        self.session = session
    }

    public func startThread(
        workingDirectory: URL,
        baseInstructions: String,
        allowFileWrites: Bool,
        disableTools: Bool = false,
        modelID: String? = nil
    ) async throws -> String {
        var params: [String: JSONValue] = [
            "cwd": .string(workingDirectory.path),
            "ephemeral": true,
            "approvalPolicy": "never",
            "sandbox": allowFileWrites ? "workspace-write" : "read-only",
            "runtimeWorkspaceRoots": [.string(workingDirectory.path)],
            "baseInstructions": .string(baseInstructions),
        ]
        if let modelID {
            params["model"] = .string(modelID)
        }
        if disableTools {
            params["dynamicTools"] = []
            params["environments"] = []
            params["selectedCapabilityRoots"] = []
            params["config"] = Self.toolFreeConfig
        }
        let response = try await session.request(
            method: "thread/start",
            params: .object(params),
            timeout: .seconds(20)
        )
        guard let threadID = response["thread"]?["id"]?.stringValue else {
            throw BookLensError.protocolViolation(code: "thread-start-shape")
        }
        return threadID
    }

    nonisolated static let toolFreeConfig: JSONValue = [
        "features": [
            "apps": false,
            "browser_use": false,
            "code_mode_host": false,
            "computer_use": false,
            "goals": false,
            "hooks": false,
            "image_generation": false,
            "in_app_browser": false,
            "multi_agent": false,
            "multi_agent_v2": false,
            "shell_tool": false,
            "unified_exec": false,
            "workspace_dependencies": false,
        ],
    ]

    public func startTurn(
        threadID: String,
        prompt: String,
        outputSchema: JSONValue? = nil,
        reasoningEffort: String? = nil
    ) async throws -> CodexTurnHandle {
        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": [["type": "text", "text": .string(prompt)]],
        ]
        if let outputSchema {
            params["outputSchema"] = outputSchema
        }
        if let reasoningEffort {
            params["effort"] = .string(reasoningEffort)
        }
        let response = try await session.request(
            method: "turn/start",
            params: .object(params),
            timeout: .seconds(20)
        )
        guard let turnID = response["turn"]?["id"]?.stringValue else {
            throw BookLensError.protocolViolation(code: "turn-start-shape")
        }
        return CodexTurnHandle(threadID: threadID, turnID: turnID)
    }

    public func waitForCompletion(
        _ handle: CodexTurnHandle,
        timeout: Duration,
        rejectToolUse: Bool = false,
        onProgress: CodexTurnProgressHandler? = nil
    ) async throws -> CodexTurnOutcome {
        let stream = session.notifications()
        return try await withThrowingTaskGroup(of: CodexTurnOutcome.self) { group in
            group.addTask {
                var finalMessage: String?
                for await notification in stream {
                    guard let params = notification.params else { continue }
                    if rejectToolUse,
                       notification.method == "item/started",
                       let itemType = params["item"]?["type"]?.stringValue,
                       Self.isToolItem(itemType)
                    {
                        throw BookLensError.protocolViolation(code: "tool-use-forbidden")
                    }
                    if let progress = Self.progress(
                        from: notification,
                        params: params,
                        matching: handle
                    ) {
                        await onProgress?(progress)
                    }
                    if notification.method == "item/completed",
                       params["threadId"]?.stringValue == handle.threadID,
                       params["turnId"]?.stringValue == handle.turnID,
                       params["item"]?["type"]?.stringValue == "agentMessage"
                    {
                        finalMessage = params["item"]?["text"]?.stringValue
                    }
                    if notification.method == "turn/completed",
                       params["threadId"]?.stringValue == handle.threadID,
                       params["turn"]?["id"]?.stringValue == handle.turnID
                    {
                        let status = params["turn"]?["status"]?.stringValue ?? "unknown"
                        let errorType = params["turn"]?["error"]?["type"]?.stringValue
                        return CodexTurnOutcome(
                            status: status,
                            finalMessage: finalMessage,
                            errorType: errorType
                        )
                    }
                }
                throw CodexProcessError.notRunning
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BookLensError.timeout(operation: "turn")
            }
            guard let outcome = try await group.next() else {
                throw CodexProcessError.notRunning
            }
            group.cancelAll()
            return outcome
        }
    }

    nonisolated static func isToolItem(_ itemType: String) -> Bool {
        let normalized = itemType.lowercased()
        return normalized.contains("command")
            || normalized.contains("tool")
            || normalized.contains("websearch")
            || normalized.contains("imagegeneration")
            || normalized.contains("filechange")
    }

    public func interrupt(_ handle: CodexTurnHandle) async throws {
        try await session.interrupt(threadID: handle.threadID, turnID: handle.turnID)
    }

    private nonisolated static func progress(
        from notification: JSONRPCNotification,
        params: JSONValue,
        matching handle: CodexTurnHandle
    ) -> CodexTurnProgress? {
        let threadID = params["threadId"]?.stringValue
        let turnID = params["turnId"]?.stringValue
            ?? params["turn"]?["id"]?.stringValue
        guard threadID == handle.threadID,
              turnID == nil || turnID == handle.turnID
        else { return nil }

        switch notification.method {
        case "turn/started", "turn/completed", "item/started", "item/completed":
            return CodexTurnProgress(
                method: notification.method,
                itemType: params["item"]?["type"]?.stringValue,
                status: params["turn"]?["status"]?.stringValue
            )
        default:
            return nil
        }
    }
}
