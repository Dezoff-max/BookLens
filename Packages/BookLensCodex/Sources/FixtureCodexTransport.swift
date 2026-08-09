import Foundation

public actor FixtureCodexTransport: CodexTransport {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var responsesByMethod: [String: [JSONValue]]
    private var started = false

    public init(responsesByMethod: [String: [JSONValue]]) {
        self.responsesByMethod = responsesByMethod
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    public nonisolated func messages() -> AsyncThrowingStream<Data, Error> {
        stream
    }

    public func start() async throws {
        started = true
    }

    public func send(_ message: Data) async throws {
        guard started,
              let request = try? JSONDecoder().decode(JSONValue.self, from: message),
              let id = request["id"],
              let method = request["method"]?.stringValue
        else {
            return
        }
        guard var queue = responsesByMethod[method], !queue.isEmpty else { return }
        let result = queue.removeFirst()
        responsesByMethod[method] = queue
        let response: JSONValue = ["id": id, "result": result]
        continuation.yield(try JSONEncoder().encode(response))
    }

    public func stop() async {
        started = false
        continuation.finish()
    }

    public func emit(method: String, params: JSONValue) throws {
        let notification: JSONValue = ["method": .string(method), "params": params]
        continuation.yield(try JSONEncoder().encode(notification))
    }

    public func disconnect(with error: Error) {
        continuation.finish(throwing: error)
    }
}
