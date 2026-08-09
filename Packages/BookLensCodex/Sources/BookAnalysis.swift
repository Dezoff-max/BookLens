import BookLensSupport
import Foundation

public struct BookAnalysisSource: Codable, Hashable, Sendable {
    public let title: String
    public let url: String
    public let excerpt: String

    public init(title: String, url: String, excerpt: String) {
        self.title = title
        self.url = url
        self.excerpt = excerpt
    }
}

public struct BookAnalysisTrait: Codable, Hashable, Sendable {
    public let category: String
    public let value: String
    public let confidence: String

    public init(category: String, value: String, confidence: String) {
        self.category = category
        self.value = value
        self.confidence = confidence
    }
}

public struct BookAnalysisCharacter: Codable, Hashable, Sendable {
    public let name: String
    public let role: String
    public let description: String
    public let aliases: [String]
    public let traits: [BookAnalysisTrait]
    public let evidence: [String]

    public init(
        name: String,
        role: String,
        description: String,
        aliases: [String],
        traits: [BookAnalysisTrait],
        evidence: [String]
    ) {
        self.name = name
        self.role = role
        self.description = description
        self.aliases = aliases
        self.traits = traits
        self.evidence = evidence
    }
}

public struct BookAnalysisResult: Codable, Hashable, Sendable {
    public let bookTitle: String
    public let author: String
    public let synopsis: String
    public let audience: String?
    public let ageMin: Int?
    public let ageMax: Int?
    public let genres: [String]?
    public let classificationConfidence: String?
    public let characters: [BookAnalysisCharacter]
    public let sources: [BookAnalysisSource]

    public init(
        bookTitle: String,
        author: String,
        synopsis: String,
        audience: String? = nil,
        ageMin: Int? = nil,
        ageMax: Int? = nil,
        genres: [String]? = nil,
        classificationConfidence: String? = nil,
        characters: [BookAnalysisCharacter],
        sources: [BookAnalysisSource]
    ) {
        self.bookTitle = bookTitle
        self.author = author
        self.synopsis = synopsis
        self.audience = audience
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.genres = genres
        self.classificationConfidence = classificationConfidence
        self.characters = characters
        self.sources = sources
    }
}

public struct BookAnalysisChapter: Hashable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

public actor BookAnalysisService {
    public init() {}

    public func analyzeImportedBook(
        title: String,
        author: String,
        chapters: [BookAnalysisChapter],
        workingDirectory: URL,
        modelID: String,
        reasoningEffort: String,
        outputLanguage: String,
        onProgress: CodexTurnProgressHandler? = nil
    ) async throws -> BookAnalysisResult {
        let excerpt = Self.makeRepresentativeExcerpt(from: chapters)
        let prompt = """
        Analyze the supplied book text as a literary editor.

        Book: \(title)
        Author: \(author)

        Identify 3–10 genuinely central characters. Do not treat body parts, unnamed titles, incidental forms of address, objects, or phrases as characters. For each character, provide a short story role, a clear description for future visualization, known physical traits, and 1–3 short exact quotes from the supplied text. Do not invent an appearance that is absent from the text; mark unknown traits with confidence `unspecified`.

        Also classify the reading audience: audience must be `children`, `teen`, or `adult`; provide a reasonable ageMin/ageMax range from 0 to 99, 1–4 genres, and classificationConfidence `low`, `medium`, or `high`. This is a library organization recommendation, not an official age rating.

        Write all user-facing result fields — synopsis, genres, role, description, category, and value — in \(outputLanguage). Preserve proper names in the conventional spelling for that language. Keep exact evidence quotes in the original text language.

        TEXT TO ANALYZE:
        \(excerpt)
        """
        return try await run(
            prompt: prompt,
            workingDirectory: workingDirectory,
            modelID: modelID,
            reasoningEffort: Self.optimizedReasoningEffort(reasoningEffort),
            allowWebResearch: false,
            onProgress: onProgress
        )
    }

    public func discoverBook(
        query: String,
        workingDirectory: URL,
        modelID: String,
        reasoningEffort: String,
        outputLanguage: String,
        onProgress: CodexTurnProgressHandler? = nil
    ) async throws -> BookAnalysisResult {
        let prompt = """
        Find the book online using the user's query: \(query)

        Search sources in any language and reconcile the original title, translations, and different name spellings. Use only lawful public sources: author or publisher pages, bibliographic catalogs, official bookstores, national libraries, and authoritative reference material. Do not use pirate libraries, fan wikis, or screen-adaptation details as evidence for the book description.

        Return the exact title and author, a concise synopsis, and 3–10 main characters. For each character, provide a role, a visualization-ready description, known physical traits, and short supporting excerpts. Add direct URLs for every source used. When appearance is not reliably described, use confidence `unspecified` and do not invent details.

        Also classify the reading audience: audience must be `children`, `teen`, or `adult`; provide recommended ageMin/ageMax values from 0 to 99, 1–4 genres, and classificationConfidence `low`, `medium`, or `high`. Do not present this as an official age rating.

        Write all user-facing result fields — bookTitle, synopsis, genres, role, description, category, and value — in \(outputLanguage). Render the author and proper names in the conventional spelling for that language. Keep source titles and exact excerpts in the source language.
        """
        return try await run(
            prompt: prompt,
            workingDirectory: workingDirectory,
            modelID: modelID,
            reasoningEffort: Self.optimizedReasoningEffort(reasoningEffort),
            allowWebResearch: true,
            onProgress: onProgress
        )
    }

    public nonisolated static func decode(_ text: String) throws -> BookAnalysisResult {
        guard let data = text.data(using: .utf8) else {
            throw BookLensError.invalidStructuredOutput
        }
        do {
            let result = try JSONDecoder().decode(BookAnalysisResult.self, from: data)
            guard !result.bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.characters.isEmpty
            else {
                throw BookLensError.invalidStructuredOutput
            }
            return result
        } catch let error as BookLensError {
            throw error
        } catch {
            throw BookLensError.invalidStructuredOutput
        }
    }

    public nonisolated static func makeRepresentativeExcerpt(
        from chapters: [BookAnalysisChapter],
        characterLimit: Int = 96_000
    ) -> String {
        guard !chapters.isEmpty, characterLimit > 0 else { return "" }
        let minimumChapterCount = chapters.count > 1 ? 2 : 1
        let chapterCount = min(
            chapters.count,
            max(minimumChapterCount, min(24, characterLimit / 4_000))
        )
        let selectedChapters = evenlySampledChapters(chapters, count: chapterCount)
        let perChapter = max(1, characterLimit / selectedChapters.count)
        var remaining = characterLimit
        var blocks: [String] = []

        for chapter in selectedChapters where remaining > 0 {
            let allowance = min(perChapter, remaining)
            let body = balancedSample(from: chapter.text, characterLimit: allowance)
            blocks.append("## \(chapter.title)\n\(body)")
            remaining -= body.count
        }
        return blocks.joined(separator: "\n\n")
    }

    public nonisolated static func optimizedReasoningEffort(_ requested: String) -> String {
        switch requested.lowercased() {
        case "high", "xhigh", "max", "ultra": "medium"
        default: requested
        }
    }

    private nonisolated static func evenlySampledChapters(
        _ chapters: [BookAnalysisChapter],
        count: Int
    ) -> [BookAnalysisChapter] {
        guard count < chapters.count, count > 1 else {
            return count == 1 ? [chapters[0]] : chapters
        }
        return (0..<count).map { position in
            let fraction = Double(position) / Double(count - 1)
            let index = Int((fraction * Double(chapters.count - 1)).rounded())
            return chapters[index]
        }
    }

    private nonisolated static func balancedSample(
        from text: String,
        characterLimit: Int
    ) -> String {
        guard text.count > characterLimit else { return text }
        let separator = "\n[…]\n"
        let separatorBudget = separator.count * 2
        guard characterLimit > separatorBudget + 6 else {
            return String(text.prefix(characterLimit))
        }

        let contentBudget = characterLimit - separatorBudget
        let firstCount = contentBudget / 3
        let middleCount = contentBudget / 3
        let lastCount = contentBudget - firstCount - middleCount
        let middleStartOffset = max(0, (text.count - middleCount) / 2)
        let middleStart = text.index(text.startIndex, offsetBy: middleStartOffset)
        let middleEnd = text.index(middleStart, offsetBy: middleCount, limitedBy: text.endIndex) ?? text.endIndex

        return String(text.prefix(firstCount))
            + separator
            + String(text[middleStart..<middleEnd])
            + separator
            + String(text.suffix(lastCount))
    }

    private func run(
        prompt: String,
        workingDirectory: URL,
        modelID: String,
        reasoningEffort: String,
        allowWebResearch: Bool,
        onProgress: CodexTurnProgressHandler?
    ) async throws -> BookAnalysisResult {
        do {
            return try await runAttempt(
                prompt: prompt,
                workingDirectory: workingDirectory,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                allowWebResearch: allowWebResearch,
                onProgress: onProgress
            )
        } catch let processError as CodexProcessError {
            await onProgress?(
                CodexTurnProgress(
                    method: "process/retrying",
                    itemType: "codex-app-server",
                    status: processError.diagnosticDetail
                )
            )
            return try await runAttempt(
                prompt: prompt,
                workingDirectory: workingDirectory,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                allowWebResearch: allowWebResearch,
                onProgress: onProgress
            )
        }
    }

    private func runAttempt(
        prompt: String,
        workingDirectory: URL,
        modelID: String,
        reasoningEffort: String,
        allowWebResearch: Bool,
        onProgress: CodexTurnProgressHandler?
    ) async throws -> BookAnalysisResult {
        let installation = try await CodexExecutableResolver().resolve()
        let session = CodexAppServerSession(installation: installation)
        _ = try await session.start()
        defer { Task { await session.stop() } }

        let account = try await session.readAccount()
        guard account.accountType == "chatgpt" else {
            throw BookLensError.authenticationRequired
        }

        let runner = CodexTurnRunner(session: session)
        let baseInstructions = allowWebResearch
            ? "Research only lawful public book sources. Return only data matching the JSON Schema. Do not read local files."
            : "Analyze only the text inside the request. Do not use model memory, the web, or local files. Return only data matching the JSON Schema."
        let threadID = try await runner.startThread(
            workingDirectory: workingDirectory,
            baseInstructions: baseInstructions,
            allowFileWrites: false,
            disableTools: !allowWebResearch,
            modelID: modelID
        )
        let handle = try await runner.startTurn(
            threadID: threadID,
            prompt: prompt,
            outputSchema: Self.outputSchema,
            reasoningEffort: reasoningEffort
        )
        let outcome = try await runner.waitForCompletion(
            handle,
            timeout: .seconds(600),
            rejectToolUse: !allowWebResearch,
            onProgress: onProgress
        )
        guard outcome.status == "completed", let message = outcome.finalMessage else {
            throw Self.mapTurnFailure(outcome.errorType, status: outcome.status)
        }
        return try Self.decode(message)
    }

    private nonisolated static func mapTurnFailure(_ errorType: String?, status: String) -> BookLensError {
        if status == "interrupted" { return .cancelled }
        switch errorType {
        case "rate_limit_reached": return .rateLimitExceeded
        case "authentication_required": return .authenticationRequired
        default: return .protocolViolation(code: errorType ?? status)
        }
    }

    private nonisolated static let outputSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["bookTitle", "author", "synopsis", "audience", "ageMin", "ageMax", "genres", "classificationConfidence", "characters", "sources"],
        "properties": [
            "bookTitle": ["type": "string"],
            "author": ["type": "string"],
            "synopsis": ["type": "string"],
            "audience": ["type": "string", "enum": ["children", "teen", "adult"]],
            "ageMin": ["type": "integer", "minimum": 0, "maximum": 99],
            "ageMax": ["type": "integer", "minimum": 0, "maximum": 99],
            "genres": [
                "type": "array",
                "minItems": 1,
                "maxItems": 4,
                "items": ["type": "string"],
            ],
            "classificationConfidence": [
                "type": "string",
                "enum": ["low", "medium", "high"],
            ],
            "characters": [
                "type": "array",
                "minItems": 1,
                "maxItems": 10,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "role", "description", "aliases", "traits", "evidence"],
                    "properties": [
                        "name": ["type": "string"],
                        "role": ["type": "string"],
                        "description": ["type": "string"],
                        "aliases": ["type": "array", "items": ["type": "string"]],
                        "traits": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "additionalProperties": false,
                                "required": ["category", "value", "confidence"],
                                "properties": [
                                    "category": ["type": "string"],
                                    "value": ["type": "string"],
                                    "confidence": [
                                        "type": "string",
                                        "enum": ["confirmed", "probable", "unspecified", "interpretation"],
                                    ],
                                ],
                            ],
                        ],
                        "evidence": ["type": "array", "maxItems": 3, "items": ["type": "string"]],
                    ],
                ],
            ],
            "sources": [
                "type": "array",
                "maxItems": 8,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title", "url", "excerpt"],
                    "properties": [
                        "title": ["type": "string"],
                        "url": ["type": "string"],
                        "excerpt": ["type": "string"],
                    ],
                ],
            ],
        ],
    ]
}
