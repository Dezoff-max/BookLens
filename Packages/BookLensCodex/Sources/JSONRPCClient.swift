import BookLensSupport
import Foundation

public struct JSONRPCNotification: Equatable, Sendable {
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.method = method
        self.params = params
    }
}

public struct JSONRPCRemoteError: Error, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public actor JSONRPCClient {
    private let transport: any CodexTransport
    private let defaultTimeout: Duration
    private let notificationStream: AsyncStream<JSONRPCNotification>
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation

    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var listenerTask: Task<Void, Never>?

    public init(transport: any CodexTransport, defaultTimeout: Duration = .seconds(20)) {
        self.transport = transport
        self.defaultTimeout = defaultTimeout
        let pair = AsyncStream<JSONRPCNotification>.makeStream()
        notificationStream = pair.stream
        notificationContinuation = pair.continuation
    }

    public nonisolated func notifications() -> AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    public func start() async throws {
        try await transport.start()
        listenerTask = Task { [weak self, transport] in
            do {
                for try await message in transport.messages() {
                    await self?.receive(message)
                }
                await self?.disconnect(with: CodexProcessError.notRunning)
            } catch {
                await self?.disconnect(with: error)
            }
        }
    }

    public func request(
        method: String,
        params: JSONValue? = nil,
        timeout: Duration? = nil
    ) async throws -> JSONValue {
        let requestID = nextRequestID
        nextRequestID += 1

        var object: [String: JSONValue] = [
            "id": .number(Double(requestID)),
            "method": .string(method),
        ]
        if let params {
            object["params"] = params
        }
        let data = try JSONEncoder().encode(JSONValue.object(object))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = continuation
                let effectiveTimeout = timeout ?? defaultTimeout
                timeoutTasks[requestID] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: effectiveTimeout)
                        await self?.expire(requestID, method: method)
                    } catch {
                        // Cancelled because the request completed.
                    }
                }
                Task { [weak self, transport] in
                    do {
                        try await transport.send(data)
                    } catch {
                        await self?.fail(requestID, with: error)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.fail(requestID, with: BookLensError.cancelled)
            }
        }
    }

    public func notify(method: String, params: JSONValue? = nil) async throws {
        var object: [String: JSONValue] = ["method": .string(method)]
        if let params {
            object["params"] = params
        }
        let data = try JSONEncoder().encode(JSONValue.object(object))
        try await transport.send(data)
    }

    public func stop() async {
        listenerTask?.cancel()
        listenerTask = nil
        disconnect(with: CodexProcessError.notRunning)
        await transport.stop()
    }

    private func receive(_ data: Data) {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = message.objectValue
        else {
            disconnect(with: BookLensError.protocolViolation(code: "invalid-json"))
            return
        }

        if let requestID = object["id"]?.intValue,
           object["result"] != nil || object["error"] != nil
        {
            timeoutTasks.removeValue(forKey: requestID)?.cancel()
            guard let continuation = pending.removeValue(forKey: requestID) else { return }
            if let result = object["result"] {
                continuation.resume(returning: result)
            } else if let error = object["error"]?.objectValue {
                continuation.resume(
                    throwing: JSONRPCRemoteError(
                        code: error["code"]?.intValue ?? -1,
                        message: error["message"]?.stringValue ?? "Unknown JSON-RPC error"
                    )
                )
            }
            return
        }

        if let method = object["method"]?.stringValue {
            notificationContinuation.yield(
                JSONRPCNotification(method: method, params: object["params"])
            )
        }
    }

    private func expire(_ requestID: Int, method: String) {
        fail(requestID, with: BookLensError.timeout(operation: method))
    }

    private func fail(_ requestID: Int, with error: Error) {
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        pending.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    private func disconnect(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
        notificationContinuation.finish()
    }
}
