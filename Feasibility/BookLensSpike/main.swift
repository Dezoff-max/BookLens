import BookLensCodex
import BookLensDomain
import BookLensSupport
import Foundation

private enum SpikeCommand: String {
    case probe
    case models
    case toolFree = "tool-free"
    case text
    case cancel
    case image
    case validate
    case all
}

@main
struct BookLensSpike {
    static func main() async {
        let command = CommandLine.arguments.dropFirst().first.flatMap(SpikeCommand.init(rawValue:)) ?? .probe
        do {
            let installation = try await CodexExecutableResolver().resolve()
            printRecord([
                "event": "installation",
                "version": installation.version,
                "architecture": installation.architecture,
                "compatible": String(installation.compatibility == .compatible),
            ])

            let session = CodexAppServerSession(installation: installation)
            let handshake = try await session.start()
            printRecord([
                "event": "handshake",
                "platform": handshake.platformOS,
                "userAgent": handshake.userAgent,
            ])

            do {
                switch command {
                case .probe:
                    try await probe(session)
                case .models:
                    try await models(session)
                case .toolFree:
                    try await toolFreeThread(session)
                case .text:
                    try await structuredText(session)
                case .cancel:
                    try await cancellation(session)
                case .image:
                    try await image(session)
                case .validate:
                    try await validateExistingImage()
                case .all:
                    try await probe(session)
                    try await structuredText(session)
                    try await cancellation(session)
                    try await image(session)
                }
                await session.stop()
            } catch {
                await session.stop()
                throw error
            }
        } catch {
            let diagnosticCode = (error as? BookLensError)?.diagnosticCode ?? "BLX-SPIKE-UNEXPECTED"
            printRecord([
                "event": "failure",
                "diagnosticCode": diagnosticCode,
                "errorType": String(describing: type(of: error)),
            ])
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func probe(_ session: CodexAppServerSession) async throws {
        let account = try await session.readAccount()
        printRecord([
            "event": "account",
            "requiresOpenAIAuth": String(account.requiresOpenAIAuth),
            "accountType": account.accountType ?? "none",
            "planType": account.planType ?? "unknown",
            "hasRateLimits": String(account.hasRateLimitSnapshot),
        ])
    }

    private static func toolFreeThread(_ session: CodexAppServerSession) async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLens-ToolFreeProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = CodexTurnRunner(session: session)
        _ = try await runner.startThread(
            workingDirectory: workspace,
            baseInstructions: "Return structured text only. Local and external tools are disabled.",
            allowFileWrites: false,
            disableTools: true
        )
        printRecord([
            "event": "toolFreeThread",
            "accepted": "true",
        ])
    }

    private static func models(_ session: CodexAppServerSession) async throws {
        for model in try await session.listModels() {
            printRecord([
                "event": "model",
                "id": model.id,
                "model": model.model,
                "displayName": model.displayName,
                "isDefault": String(model.isDefault),
                "defaultEffort": model.defaultReasoningEffort,
                "efforts": model.supportedReasoningEfforts.map(\.value).joined(separator: ","),
            ])
        }
    }

    private static func structuredText(_ session: CodexAppServerSession) async throws {
        guard try await session.readAccount().accountType == "chatgpt" else {
            throw BookLensError.authenticationRequired
        }
        let catalog = try await session.listModels()
        let requestedID = CommandLine.arguments.dropFirst(2).first
        guard let model = requestedID.flatMap({ id in catalog.first { $0.id == id } })
            ?? (requestedID == nil ? catalog.first(where: \.isDefault) : nil) else {
            throw BookLensError.protocolViolation(code: "probe-model-unavailable")
        }
        let effort = model.supportedReasoningEfforts.contains { $0.value == "low" }
            ? "low" : model.defaultReasoningEffort
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLens-TextProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = CodexTurnRunner(session: session)
        let threadID = try await runner.startThread(
            workingDirectory: workspace,
            baseInstructions: "Answer only with the requested structured data. Do not use tools.",
            allowFileWrites: false,
            disableTools: true,
            modelID: model.model
        )
        let schema: JSONValue = [
            "type": "object",
            "additionalProperties": false,
            "required": ["probe", "value"],
            "properties": [
                "probe": ["type": "string", "enum": ["booklens"]],
                "value": ["type": "integer"],
            ],
        ]
        let handle = try await runner.startTurn(
            threadID: threadID,
            prompt: "Return probe booklens and value 42.",
            outputSchema: schema,
            reasoningEffort: effort
        )
        let outcome = try await runner.waitForCompletion(handle, timeout: .seconds(120), rejectToolUse: true)
        guard outcome.status == "completed", let finalMessage = outcome.finalMessage,
              let data = finalMessage.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["probe"] as? String == "booklens",
              object["value"] as? Int == 42
        else {
            throw BookLensError.invalidStructuredOutput
        }
        printRecord([
            "event": "structuredText",
            "model": model.model,
            "effort": effort,
            "status": outcome.status,
            "valid": "true",
        ])
    }

    private static func cancellation(_ session: CodexAppServerSession) async throws {
        let runner = CodexTurnRunner(session: session)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let threadID = try await runner.startThread(
            workingDirectory: root,
            baseInstructions: "Use the shell tool exactly as requested so cancellation can be verified.",
            allowFileWrites: false
        )
        let handle = try await runner.startTurn(
            threadID: threadID,
            prompt: "Run /bin/sleep 30 once, then reply with the word finished."
        )
        try await Task.sleep(for: .seconds(1))
        try await runner.interrupt(handle)
        let outcome = try await runner.waitForCompletion(handle, timeout: .seconds(30))
        guard outcome.status != "completed" else {
            throw BookLensError.protocolViolation(code: "late-success-after-cancel")
        }
        printRecord([
            "event": "cancellation",
            "status": outcome.status,
            "lateSuccess": "false",
        ])
    }

    private static func image(_ session: CodexAppServerSession) async throws {
        let jobID = UUID()
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".booklens-spike/Jobs/\(jobID.uuidString.lowercased())", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let validator = ImageArtifactValidator()
        let before = try validator.snapshot(directory: output)

        let runner = CodexTurnRunner(session: session)
        let threadID = try await runner.startThread(
            workingDirectory: root,
            baseInstructions: "Complete exactly the requested image task. Do not inspect unrelated files.",
            allowFileWrites: true
        )
        let prompt = """
        $imagegen
        Create one original bookplate-style illustration: a closed antique book on a neutral warm paper background, no people, no logos, and no readable text.
        Save exactly one final PNG or JPEG inside this existing output directory: \(output.path)
        Do not save the final file anywhere else.
        """
        let handle = try await runner.startTurn(threadID: threadID, prompt: prompt)
        let outcome = try await runner.waitForCompletion(handle, timeout: .seconds(600))
        guard outcome.status == "completed" else {
            throw mapTurnFailure(outcome.errorType)
        }
        let artifact = try await validator.waitForNewImage(
            in: output,
            excluding: before,
            timeout: .seconds(30)
        )
        printRecord([
            "event": "image",
            "jobID": jobID.uuidString.lowercased(),
            "status": outcome.status,
            "sha256": artifact.sha256,
            "width": String(artifact.pixelWidth),
            "height": String(artifact.pixelHeight),
            "bytes": String(artifact.byteCount),
        ])
    }

    private static func validateExistingImage() async throws {
        guard CommandLine.arguments.count >= 3 else {
            throw BookLensError.invalidOutputPath
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        )
        printRecord([
            "event": "imageValidationInput",
            "argumentCount": String(CommandLine.arguments.count),
            "directoryName": output.deletingLastPathComponent().lastPathComponent,
            "fileCount": String(files.count),
        ])
        guard files.count == 1 else {
            throw files.isEmpty ? BookLensError.outputFileMissing : BookLensError.multipleOutputFiles
        }
        let artifact = try ImageArtifactValidator().validate(files[0], inside: output)
        printRecord([
            "event": "imageValidation",
            "sha256": artifact.sha256,
            "width": String(artifact.pixelWidth),
            "height": String(artifact.pixelHeight),
            "bytes": String(artifact.byteCount),
        ])
    }

    private static func mapTurnFailure(_ errorType: String?) -> Error {
        switch errorType {
        case "rate_limit_reached": BookLensError.rateLimitExceeded
        case "authentication_required": BookLensError.authenticationRequired
        default: BookLensError.protocolViolation(code: errorType ?? "turn-failed")
        }
    }

    private static func printRecord(_ record: [String: String]) {
        let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(data.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
    }
}
