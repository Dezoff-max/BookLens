import BookLensCodex
import BookLensData
import BookLensDomain
import BookLensSupport
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BookAnalysisController {
    enum State: Equatable {
        case idle
        case analyzing
        case ready
        case failed(String)
    }

    var state: State = .idle
    var statusText = BookLensLocalization.string("AI is reading the book and finding its main characters…")
    var startedAt: Date?
    var finishedAt: Date?

    private var task: Task<Void, Never>?

    var isAnalyzing: Bool { state == .analyzing }

    var completedDuration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(finishedAt.timeIntervalSince(startedAt), 0)
    }

    func analyze(book: BookRecord, model: AppModel, modelContext: ModelContext) {
        guard !isAnalyzing, model.canUseAI else { return }
        let chapters = book.chapters
            .sorted { $0.index < $1.index }
            .map { BookAnalysisChapter(title: $0.title, text: $0.text) }
        guard !chapters.isEmpty else {
            state = .failed(BookLensLocalization.string("The book has no text to analyze"))
            return
        }

        state = .analyzing
        startedAt = .now
        finishedAt = nil
        statusText = BookLensLocalization.string("AI is understanding the story and separating characters from incidental names…")
        book.analysisStatus = "analyzing"
        try? modelContext.save()

        let title = book.title
        let author = book.author
        let modelID = model.selectedModelID
        let effort = model.selectedReasoningEffort
        let outputLanguage = model.analysisOutputLanguage
        let operationID = UUID().uuidString.lowercased()
        let operationStartedAt = startedAt ?? .now
        let chapterCharacterCount = chapters.reduce(0) { $0 + $1.text.count }

        task = Task {
            let diagnostics = BookLensDiagnostics.shared
            var heartbeat: Task<Void, Never>?
            defer { heartbeat?.cancel() }
            await diagnostics.record("book-analysis.started", fields: [
                "operation": operationID,
                "book": book.id.uuidString.lowercased(),
                "chapters": String(chapters.count),
                "source_characters": String(chapterCharacterCount),
                "model": modelID,
                "requested_effort": effort,
                "effective_effort": BookAnalysisService.optimizedReasoningEffort(effort),
                "output_language": outputLanguage,
            ])
            heartbeat = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(15))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    await diagnostics.record("book-analysis.waiting", fields: [
                        "operation": operationID,
                        "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    ])
                }
            }
            do {
                let workingDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BookLens-Analysis-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: workingDirectory) }
                let result = try await BookAnalysisService().analyzeImportedBook(
                    title: title,
                    author: author,
                    chapters: chapters,
                    workingDirectory: workingDirectory,
                    modelID: modelID,
                    reasoningEffort: effort,
                    outputLanguage: outputLanguage
                ) { progress in
                    await diagnostics.record("book-analysis.codex-event", fields: [
                        "operation": operationID,
                        "method": progress.method,
                        "item_type": progress.itemType ?? "none",
                        "status": progress.status ?? "none",
                    ])
                }
                apply(result, to: book, modelContext: modelContext)
                state = .ready
                statusText = BookLensLocalization.string("Main characters found")
                await diagnostics.record("book-analysis.completed", fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "success",
                    "characters": String(result.characters.count),
                ])
            } catch is CancellationError {
                book.analysisStatus = "pending"
                state = .idle
                statusText = BookLensLocalization.string("Analysis stopped")
                await diagnostics.record("book-analysis.finished", fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "cancelled",
                    "code": BookLensError.cancelled.diagnosticCode,
                ])
            } catch let error as BookLensError {
                book.analysisStatus = "failed"
                let message: String
                if case .timeout = error {
                    message = BookLensLocalization.string("This large book needs more time. Select Retry analysis — BookLens will now give AI enough time to finish.")
                } else {
                    message = error.localizedDescription
                }
                state = .failed(message)
                statusText = message
                await diagnostics.record("book-analysis.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": error.diagnosticCode,
                ])
            } catch let processError as CodexProcessError {
                book.analysisStatus = "failed"
                let message = BookLensLocalization.string("Codex stopped unexpectedly during analysis. Try again.")
                state = .failed(message)
                statusText = message
                await diagnostics.record("book-analysis.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": "BLX-CODEX-PROCESS",
                    "detail": processError.diagnosticDetail,
                ])
            } catch let remoteError as JSONRPCRemoteError {
                book.analysisStatus = "failed"
                let message = BookLensLocalization.string("Codex rejected the analysis request. Try again.")
                state = .failed(message)
                statusText = message
                await diagnostics.record("book-analysis.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": "BLX-RPC-REMOTE",
                    "detail": "json-rpc-remote-\(remoteError.code)",
                ])
            } catch {
                book.analysisStatus = "failed"
                state = .failed(BookLensLocalization.string("Couldn’t analyze the book"))
                statusText = BookLensLocalization.string("Couldn’t analyze the book")
                await diagnostics.record("book-analysis.finished", level: .error, fields: [
                    "operation": operationID,
                    "elapsed_seconds": String(Int(Date.now.timeIntervalSince(operationStartedAt))),
                    "result": "failure",
                    "code": "BLX-ANALYSIS-UNEXPECTED",
                    "error_type": String(reflecting: type(of: error)),
                ])
            }
            heartbeat?.cancel()
            heartbeat = nil
            finishedAt = .now
            try? modelContext.save()
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func apply(_ result: BookAnalysisResult, to book: BookRecord, modelContext: ModelContext) {
        book.synopsis = result.synopsis
        book.analysisStatus = "ready"
        applyClassification(result, to: book)
        if book.author == "Author not specified", !result.author.isEmpty {
            book.author = result.author
        }

        for candidate in book.characters {
            candidate.isMainCharacter = false
            if candidate.origin == "candidate" || candidate.role.isEmpty {
                candidate.isExcluded = true
            }
        }

        let orderedChapters = book.chapters.sorted { $0.index < $1.index }
        let extractedChapters = orderedChapters.map { ExtractedChapter(title: $0.title, text: $0.text) }

        for analyzed in result.characters {
            let character = matchingCharacter(for: analyzed, in: book)
                ?? CharacterRecord(name: analyzed.name)
            if character.book == nil {
                book.characters.append(character)
            }
            character.name = analyzed.name
            character.aliases = analyzed.aliases
            character.role = analyzed.role
            character.summary = analyzed.description
            character.isMainCharacter = true
            character.isExcluded = false
            character.origin = "ai-local"

            var evidenceIDs = persistEvidence(
                analyzed.evidence,
                characterName: analyzed.name,
                chapters: orderedChapters
            )
            if evidenceIDs.isEmpty {
                let mentions = CharacterMentionFinder().find(name: analyzed.name, in: extractedChapters)
                character.occurrenceCount = mentions.occurrenceCount
                for found in mentions.evidence where found.chapterIndex < orderedChapters.count {
                    let digest = SHA256Digest.string(for: found.excerpt)
                    if let existing = orderedChapters[found.chapterIndex].evidence.first(where: { $0.digest == digest }) {
                        evidenceIDs.append(existing.id)
                    } else {
                        let record = EvidenceRecord(
                            id: found.id,
                            characterName: analyzed.name,
                            text: found.excerpt,
                            rangeStart: found.localRange.lowerBound,
                            rangeEnd: found.localRange.upperBound,
                            digest: digest
                        )
                        orderedChapters[found.chapterIndex].evidence.append(record)
                        evidenceIDs.append(record.id)
                    }
                }
            } else {
                character.occurrenceCount = max(character.occurrenceCount, evidenceIDs.count)
            }

            for oldTrait in character.traits {
                modelContext.delete(oldTrait)
            }
            let analyzedTraits = analyzed.traits.isEmpty
                ? [BookAnalysisTrait(category: "General description", value: analyzed.description, confidence: evidenceIDs.isEmpty ? "interpretation" : "probable")]
                : analyzed.traits
            character.traits = analyzedTraits.map { trait in
                let requested = TraitConfidence(rawValue: trait.confidence) ?? .unspecified
                let confidence: TraitConfidence = evidenceIDs.isEmpty && [.confirmed, .probable].contains(requested)
                    ? .unspecified
                    : requested
                return TraitRecord(
                    category: trait.category,
                    value: trait.value,
                    confidence: confidence.rawValue,
                    evidenceIDs: confidence == .unspecified ? [] : evidenceIDs
                )
            }
        }

        book.characterCount = book.characters.filter { $0.isMainCharacter && !$0.isExcluded }.count
        try? modelContext.save()
    }

    static func makeWebBook(from result: BookAnalysisResult) -> BookRecord {
        var chapters: [ChapterRecord] = result.sources.enumerated().map { index, source in
            ChapterRecord(
                index: index,
                title: source.title,
                text: source.excerpt,
                rangeStart: 0,
                rangeEnd: source.excerpt.count,
                evidence: []
            )
        }
        if chapters.isEmpty {
            chapters = [ChapterRecord(index: 0, title: "Description", text: result.synopsis, rangeStart: 0, rangeEnd: result.synopsis.count)]
        }

        let characters = result.characters.map { analyzed -> CharacterRecord in
            let character = CharacterRecord(
                name: analyzed.name,
                aliases: analyzed.aliases,
                occurrenceCount: analyzed.evidence.count,
                isMainCharacter: true,
                role: analyzed.role,
                summary: analyzed.description,
                origin: "ai-web"
            )
            let evidenceIDs = analyzed.evidence.enumerated().map { index, excerpt -> UUID in
                let record = EvidenceRecord(
                    characterName: analyzed.name,
                    text: excerpt,
                    rangeStart: 0,
                    rangeEnd: excerpt.count,
                    digest: SHA256Digest.string(for: excerpt),
                    sourceURL: result.sources.indices.contains(index) ? result.sources[index].url : result.sources.first?.url
                )
                chapters[min(index, chapters.count - 1)].evidence.append(record)
                return record.id
            }
            let analyzedTraits = analyzed.traits.isEmpty
                ? [BookAnalysisTrait(category: "General description", value: analyzed.description, confidence: evidenceIDs.isEmpty ? "interpretation" : "probable")]
                : analyzed.traits
            character.traits = analyzedTraits.map { trait in
                let requested = TraitConfidence(rawValue: trait.confidence) ?? .unspecified
                let confidence: TraitConfidence = evidenceIDs.isEmpty && [.confirmed, .probable].contains(requested)
                    ? .unspecified
                    : requested
                return TraitRecord(
                    category: trait.category,
                    value: trait.value,
                    confidence: confidence.rawValue,
                    evidenceIDs: confidence == .unspecified ? [] : evidenceIDs
                )
            }
            return character
        }

        return BookRecord(
            title: result.bookTitle,
            author: result.author,
            sourceFilename: "Online sources",
            storedSourcePath: "",
            analysisStatus: "ready",
            synopsis: result.synopsis,
            sourceKind: "web",
            sourceURL: result.sources.first?.url,
            audience: normalizedAudience(result.audience),
            ageMin: normalizedAge(result.ageMin),
            ageMax: normalizedAge(result.ageMax),
            genres: normalizedGenres(result.genres),
            classificationConfidence: normalizedConfidence(result.classificationConfidence),
            chapters: chapters,
            characters: characters
        )
    }

    private func applyClassification(_ result: BookAnalysisResult, to book: BookRecord) {
        book.audience = Self.normalizedAudience(result.audience)
        book.ageMin = Self.normalizedAge(result.ageMin)
        book.ageMax = max(Self.normalizedAge(result.ageMax), book.ageMin)
        book.genres = Self.normalizedGenres(result.genres)
        book.classificationConfidence = Self.normalizedConfidence(result.classificationConfidence)
    }

    private static func normalizedAudience(_ value: String?) -> String {
        guard let value, ["children", "teen", "adult"].contains(value) else { return "unspecified" }
        return value
    }

    private static func normalizedAge(_ value: Int?) -> Int {
        min(max(value ?? 0, 0), 99)
    }

    private static func normalizedGenres(_ values: [String]?) -> [String] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return clean
        }.prefix(4).map { $0 }
    }

    private static func normalizedConfidence(_ value: String?) -> String {
        guard let value, ["low", "medium", "high"].contains(value) else { return "unspecified" }
        return value
    }

    private func matchingCharacter(for analyzed: BookAnalysisCharacter, in book: BookRecord) -> CharacterRecord? {
        let names = Set(([analyzed.name] + analyzed.aliases).map { $0.lowercased() })
        return book.characters.first { candidate in
            names.contains(candidate.name.lowercased())
                || !names.isDisjoint(with: candidate.aliases.map { $0.lowercased() })
        }
    }

    private func persistEvidence(
        _ excerpts: [String],
        characterName: String,
        chapters: [ChapterRecord]
    ) -> [UUID] {
        var ids: [UUID] = []
        for excerpt in excerpts {
            let clean = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 8 else { continue }
            let digest = SHA256Digest.string(for: clean)
            if let existing = chapters.lazy.flatMap({ $0.evidence }).first(where: { $0.digest == digest }) {
                ids.append(existing.id)
                continue
            }
            guard let chapter = chapters.first(where: {
                $0.text.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }), let range = chapter.text.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let start = chapter.text.distance(from: chapter.text.startIndex, to: range.lowerBound)
            let end = chapter.text.distance(from: chapter.text.startIndex, to: range.upperBound)
            let record = EvidenceRecord(
                characterName: characterName,
                text: clean,
                rangeStart: start,
                rangeEnd: end,
                digest: digest
            )
            chapter.evidence.append(record)
            ids.append(record.id)
        }
        return ids
    }
}
