@preconcurrency import Foundation

public protocol CodexTransport: Sendable {
    func start() async throws
    func send(_ message: Data) async throws
    nonisolated func messages() -> AsyncThrowingStream<Data, Error>
    func stop() async
}

public actor CodexProcessController: CodexTransport {
    private let executableURL: URL
    private let messageStream: AsyncThrowingStream<Data, Error>
    private let messageContinuation: AsyncThrowingStream<Data, Error>.Continuation

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var inputHandle: FileHandle?
    private var stdoutFramer = LineFramer()
    private var stderrByteCount = 0

    public init(executableURL: URL) {
        self.executableURL = executableURL
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        messageStream = pair.stream
        messageContinuation = pair.continuation
    }

    public nonisolated func messages() -> AsyncThrowingStream<Data, Error> {
        messageStream
    }

    public func start() async throws {
        guard process == nil else { return }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = CodexProcessEnvironment.augmented()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.processTerminated(status: process.terminationStatus)
            }
        }

        try process.run()
        self.process = process
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        inputHandle = stdin.fileHandleForWriting

        let stdoutHandle = stdout.fileHandleForReading
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { await self?.receiveStdout(data) }
        }

        let stderrHandle = stderr.fileHandleForReading
        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { await self?.recordStderr(byteCount: data.count) }
        }
    }

    public func send(_ message: Data) async throws {
        guard let inputHandle, process?.isRunning == true else {
            throw CodexProcessError.notRunning
        }
        var framed = message
        framed.append(0x0A)
        try inputHandle.write(contentsOf: framed)
    }

    public func stop() async {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        try? inputHandle?.close()
        inputHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        self.process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func receiveStdout(_ data: Data) {
        do {
            let lines = try stdoutFramer.append(data)
            for line in lines {
                messageContinuation.yield(line)
            }
        } catch {
            messageContinuation.finish(throwing: error)
        }
    }

    private func processTerminated(status: Int32) {
        messageContinuation.finish(
            throwing: CodexProcessError.exited(
                status: status,
                stderrByteCount: stderrByteCount
            )
        )
    }

    private func recordStderr(byteCount: Int) {
        stderrByteCount += byteCount
    }
}

public enum CodexProcessError: Error, Equatable, Sendable {
    case notRunning
    case exited(status: Int32, stderrByteCount: Int)

    public var diagnosticDetail: String {
        switch self {
        case .notRunning:
            "not-running"
        case let .exited(status, stderrByteCount):
            "exited-status-\(status)-stderr-bytes-\(stderrByteCount)"
        }
    }
}
