import BookLensDomain
import Foundation
import UniformTypeIdentifiers

public struct ExtractedChapter: Codable, Hashable, Sendable {
    public var title: String
    public var text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

public struct ExtractedBook: Codable, Hashable, Sendable {
    public var title: String?
    public var author: String?
    public var language: String?
    public var chapters: [ExtractedChapter]

    public init(
        title: String? = nil,
        author: String? = nil,
        language: String? = nil,
        chapters: [ExtractedChapter]
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.chapters = chapters
    }

    public var characterCount: Int {
        chapters.reduce(0) { $0 + $1.text.count }
    }
}

public protocol BookTextExtractor: Sendable {
    func supports(_ type: UTType) -> Bool
    func extract(from url: URL) async throws -> ExtractedBook
}

public enum ImportStage: String, CaseIterable, Sendable {
    case validating
    case copying
    case extracting
    case splittingChapters
    case normalizing
    case indexing
    case findingNames
    case finished
}

public struct NameCandidate: Identifiable, Codable, Hashable, Sendable {
    public var id: String { normalizedName }
    public let name: String
    public let normalizedName: String
    public let occurrenceCount: Int
    public let evidence: [CandidateEvidence]

    public init(name: String, occurrenceCount: Int, evidence: [CandidateEvidence]) {
        self.name = name
        normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        self.occurrenceCount = occurrenceCount
        self.evidence = evidence
    }
}

public struct CandidateEvidence: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let chapterIndex: Int
    public let excerpt: String
    public let localRange: Range<Int>

    public init(
        id: UUID = UUID(),
        chapterIndex: Int,
        excerpt: String,
        localRange: Range<Int>
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.excerpt = excerpt
        self.localRange = localRange
    }
}

public struct ImportedBook: Sendable {
    public let book: Book
    public let storedSourceURL: URL
    public let coverURL: URL?
    public let coverSource: String
    public let chapters: [Chapter]
    public let nameCandidates: [NameCandidate]

    public init(
        book: Book,
        storedSourceURL: URL,
        coverURL: URL? = nil,
        coverSource: String = "none",
        chapters: [Chapter],
        nameCandidates: [NameCandidate]
    ) {
        self.book = book
        self.storedSourceURL = storedSourceURL
        self.coverURL = coverURL
        self.coverSource = coverSource
        self.chapters = chapters
        self.nameCandidates = nameCandidates
    }
}
