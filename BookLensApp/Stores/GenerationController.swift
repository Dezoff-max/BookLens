import BookLensCodex
import BookLensData
import BookLensDomain
import BookLensSupport
import Foundation
import Observation

struct GenerationRequest: Sendable {
    let bookID: UUID
    let bookTitle: String
    let bookAuthor: String
    let bookSynopsis: String
    let importantCharacters: [String]
    let characterID: UUID
    let profile: CharacterProfileSnapshot
    let evidenceByID: [UUID: String]
    let settings: GenerationSettings
    let references: [GenerationReference]
    let modelID: String
    let reasoningEffort: String
}

struct GeneratedArtwork: Sendable {
    let artwork: Artwork
    let storedURL: URL
    let style: String
}

@MainActor
@Observable
final class GenerationController {
    var state: GenerationState = .draft
    var statusText = BookLensLocalization.string("Ready to create")
    var error: BookLensError?
    var generated: GeneratedArtwork?
    var promptPreview = ""
    var startedAt: Date?
    var finishedAt: Date?

    private var task: Task<Void, Never>?
    private var activeRunner: CodexTurnRunner?
    private var activeHandle: CodexTurnHandle?
    private var cancellationRequested = false

    var isRunning: Bool {
        [.queued, .running, .saving].contains(state)
    }

    var completedDuration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(finishedAt.timeIntervalSince(startedAt), 0)
    }

    nonisolated static func optimizedReasoningEffort(_ requested: String) -> String {
        switch requested.lowercased() {
        case "high", "xhigh", "max", "ultra": "medium"
        default: requested
        }
    }

    func preparePrompt(_ request: GenerationRequest, outputDirectory: URL) {
        promptPreview = (try? PromptBuilder().build(
            profile: request.profile,
            availableEvidenceIDs: Set(request.evidenceByID.keys),
            evidenceByID: request.evidenceByID,
            bookContext: BookPromptContext(
                title: request.bookTitle,
                author: request.bookAuthor,
                synopsis: request.bookSynopsis,
                importantCharacters: request.importantCharacters
            ),
            settings: request.settings,
            references: request.references,
            outputDirectory: outputDirectory
        )) ?? BookLensLocalization.string("The prompt is unavailable because the profile did not pass source validation.")
    }

    func generate(
        request: GenerationRequest,
        storage: FileStorage,
        onSuccess: @escaping @MainActor (GeneratedArtwork) -> Void
    ) {
        guard !isRunning else { return }
        cancellationRequested = false
        error = nil
        generated = nil
        startedAt = .now
        finishedAt = nil
        state = .queued
        statusText = BookLensLocalization.string("Generation queued")

        task = Task {
            var domainJob = GenerationJob(
                characterID: request.characterID,
                profileSnapshotID: request.profile.id
            )
            let diagnostics = BookLensDiagnostics.shared
            let operationID = domainJob.id.uuidString.lowercased()
            let effectiveEffort = Self.optimizedReasoningEffort(request.reasoningEffort)
            let operationStartedAt = startedAt ?? .now
            var heartbeat: Task<Void, Never>?
            defer { heartbeat?.cancel() }

            await diagnostics.record("image.started", fields: [
                "operation": operationID,
                "composition": request.settings.composition.rawValue,
                "model": request.modelID,
                "requested_effort": request.reasoningEffort,
                "effective_effort": effectiveEffort,
                "evidence_count": String(request.evidenceByID.count),
                "reference_count": String(request.references.count),
            ])
            do {
                try domainJob.transition(to: .queued)
                let jobRoot = try await storage.createJobWorkspace(jobID: domainJob.id)
                let outputDirectory = jobRoot.appendingPathComponent("output", isDirectory: true)
                let validator = ImageArtifactValidator()
                let before = try validator.snapshot(directory: outputDirectory)
                preparePrompt(request, outputDirectory: outputDirectory)
                await diagnostics.record("image.workspace-ready", fields: [
                    "operation": operationID,
                    "prompt_characters": String(promptPreview.count),
                ])

                statusText = BookLensLocalization.string("Checking Codex and account")
                let installation = try await CodexExecutableResolver().resolve()
                await diagnostics.record("image.codex-resolved", fields: [
                    "operation": operationID,
                    "version": installation.version,
                    "architecture": installation.architecture,
                ])
                let session = CodexAppServerSession(installation: installation)
                _ = try await session.start()
                await diagnostics.record("image.session-ready", fields: ["operation": operationID])
                defer { Task { await session.stop() } }
                let account = try await session.readAccount()
                guard account.accountType == "chatgpt" else {
                    throw BookLensError.authenticationRequired
                }
                await diagnostics.record("image.account-ready", fields: ["operation": operationID])

                try domainJob.transition(to: .running)
                state = .running
                statusText = BookLensLocalization.string("Codex is creating the image")
                let runner = CodexTurnRunner(session: session)
                activeRunner = runner
                let threadID = try await runner.startThread(
                    workingDirectory: jobRoot,
                    baseInstructions: "Follow only the BookLens request. Do not read files outside the job workspace. Do not log the prompt or private data.",
                    allowFileWrites: true,
                    modelID: request.modelID
                )
                await diagnostics.record("image.thread-started", fields: ["operation": operationID])
                let handle = try await runner.startTurn(
                    threadID: threadID,
                    prompt: promptPreview,
                    reasoningEffort: effectiveEffort
                )
                activeHandle = handle
                await diagnostics.record("image.turn-started", fields: ["operation": operationID])
                heartbeat = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(30))
                        } catch {
                            break
                        }
                        guard !Task.isCancelled else { break }
                        await diagnostics.record("image.waiting", fields: [
                            "operation": operationID,
                            "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                        ])
                    }
                }
                let outcome = try await runner.waitForCompletion(
                    handle,
                    timeout: .seconds(600)
                ) { progress in
                    await diagnostics.record("image.codex-event", fields: [
                        "operation": operationID,
                        "method": progress.method,
                        "item_type": progress.itemType ?? "none",
                        "status": progress.status ?? "none",
                    ])
                }
                heartbeat?.cancel()
                heartbeat = nil
                await diagnostics.record("image.turn-finished", fields: [
                    "operation": operationID,
                    "status": outcome.status,
                    "error_type": outcome.errorType ?? "none",
                ])

                guard !cancellationRequested else {
                    throw BookLensError.cancelled
                }
                guard outcome.status == "completed" else {
                    throw mapTurnFailure(outcome.errorType, status: outcome.status)
                }

                try domainJob.transition(to: .saving)
                state = .saving
                statusText = BookLensLocalization.string("Validating the image and SHA-256")
                let validated = try await validator.waitForNewImage(
                    in: outputDirectory,
                    excluding: before,
                    timeout: .seconds(30)
                )
                await diagnostics.record("image.validated", fields: [
                    "operation": operationID,
                    "width": String(validated.pixelWidth),
                    "height": String(validated.pixelHeight),
                    "bytes": String(validated.byteCount),
                ])
                let artworkID = UUID()
                let storedURL = try await storage.moveValidatedArtwork(
                    from: validated.url,
                    artworkID: artworkID
                )
                let artwork = Artwork(
                    id: artworkID,
                    jobID: domainJob.id,
                    characterID: request.characterID,
                    filename: storedURL.lastPathComponent,
                    sha256: validated.sha256,
                    pixelWidth: validated.pixelWidth,
                    pixelHeight: validated.pixelHeight
                )
                try domainJob.transition(to: .succeeded, artworkID: artwork.id)
                let result = GeneratedArtwork(
                    artwork: artwork,
                    storedURL: storedURL,
                    style: request.settings.style.rawValue
                )
                generated = result
                state = .succeeded
                statusText = BookLensLocalization.string("Image validated and saved")
                activeRunner = nil
                activeHandle = nil
                onSuccess(result)
                await diagnostics.record("image.completed", fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "success",
                ])
            } catch is CancellationError {
                state = .cancelled
                statusText = BookLensLocalization.string("Generation cancelled")
                error = .cancelled
                await diagnostics.record("image.finished", fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "cancelled",
                    "code": BookLensError.cancelled.diagnosticCode,
                ])
            } catch let typed as BookLensError {
                state = typed == .cancelled ? .cancelled : .failed
                statusText = BookLensLocalization.string(typed == .cancelled ? "Generation cancelled" : "Generation failed")
                error = typed
                await diagnostics.record("image.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": typed.diagnosticCode,
                ])
            } catch let processError as CodexProcessError {
                let mapped = BookLensError.protocolViolation(code: processError.diagnosticDetail)
                state = .failed
                statusText = BookLensLocalization.string("Codex stopped unexpectedly. Try generating again.")
                self.error = mapped
                await diagnostics.record("image.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": mapped.diagnosticCode,
                    "detail": processError.diagnosticDetail,
                ])
            } catch let remoteError as JSONRPCRemoteError {
                let mapped = BookLensError.protocolViolation(code: "json-rpc-remote-\(remoteError.code)")
                state = .failed
                statusText = BookLensLocalization.string("Codex rejected the request. Check the log and try again.")
                self.error = mapped
                await diagnostics.record("image.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": mapped.diagnosticCode,
                    "detail": "json-rpc-remote-\(remoteError.code)",
                ])
            } catch {
                state = .failed
                statusText = BookLensLocalization.string("Generation failed")
                self.error = .protocolViolation(code: "unexpected-generation-error")
                await diagnostics.record("image.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": "BLX-GENERATION-UNEXPECTED",
                    "error_type": String(reflecting: type(of: error)),
                ])
            }
            activeRunner = nil
            activeHandle = nil
            finishedAt = .now
            task = nil
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancellationRequested = true
        statusText = BookLensLocalization.string("Cancelling the active generation…")
        let runner = activeRunner
        let handle = activeHandle
        Task {
            if let runner, let handle {
                try? await runner.interrupt(handle)
            }
            task?.cancel()
        }
    }

    func resetForRetry() {
        guard !isRunning else { return }
        state = .draft
        statusText = BookLensLocalization.string("Ready to try again")
        error = nil
        startedAt = nil
        finishedAt = nil
    }

    private func mapTurnFailure(_ errorType: String?, status: String) -> BookLensError {
        if status == "interrupted" { return .cancelled }
        switch errorType {
        case "rate_limit_reached": return .rateLimitExceeded
        case "authentication_required": return .authenticationRequired
        default: return .protocolViolation(code: errorType ?? status)
        }
    }
}
