import Foundation

public struct Book: Identifiable, Codable, Hashable, Sendable {
    public enum ProcessingStatus: String, Codable, Sendable {
        case importing
        case ready
        case failed
    }

    public let id: UUID
    public var title: String
    public var author: String
    public var language: String?
    public var publicationYear: Int?
    public var sourceFilename: String
    public var status: ProcessingStatus
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        author: String,
        language: String? = nil,
        publicationYear: Int? = nil,
        sourceFilename: String,
        status: ProcessingStatus = .ready,
        importedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.language = language
        self.publicationYear = publicationYear
        self.sourceFilename = sourceFilename
        self.status = status
        self.importedAt = importedAt
    }
}

public struct Chapter: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public var index: Int
    public var title: String
    public var text: String
    public var normalizedRange: Range<Int>

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        index: Int,
        title: String,
        text: String,
        normalizedRange: Range<Int>
    ) {
        self.id = id
        self.bookID = bookID
        self.index = index
        self.title = title
        self.text = text
        self.normalizedRange = normalizedRange
    }
}

public struct TextChunk: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let chapterID: UUID
    public var index: Int
    public var text: String
    public var normalizedRange: Range<Int>
    public var digest: String

    public init(
        id: UUID = UUID(),
        chapterID: UUID,
        index: Int,
        text: String,
        normalizedRange: Range<Int>,
        digest: String
    ) {
        self.id = id
        self.chapterID = chapterID
        self.index = index
        self.text = text
        self.normalizedRange = normalizedRange
        self.digest = digest
    }
}

public struct Character: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public var name: String
    public var aliases: [CharacterAlias]
    public var isExcluded: Bool

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        aliases: [CharacterAlias] = [],
        isExcluded: Bool = false
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.aliases = aliases
        self.isExcluded = isExcluded
    }
}

public struct CharacterAlias: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var value: String

    public init(id: UUID = UUID(), value: String) {
        self.id = id
        self.value = value
    }
}

public enum TraitConfidence: String, Codable, CaseIterable, Sendable {
    case confirmed
    case probable
    case unspecified
    case interpretation
}

public struct CharacterTrait: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var category: String
    public var value: String
    public var confidence: TraitConfidence
    public var evidenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        category: String,
        value: String,
        confidence: TraitConfidence,
        evidenceIDs: [UUID] = []
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.confidence = confidence
        self.evidenceIDs = evidenceIDs
    }
}

public struct EvidenceFragment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let chapterID: UUID
    public var chapterTitle: String
    public var text: String
    public var normalizedRange: Range<Int>
    public var digest: String
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterID: UUID,
        chapterTitle: String,
        text: String,
        normalizedRange: Range<Int>,
        digest: String,
        isSelected: Bool = true
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.text = text
        self.normalizedRange = normalizedRange
        self.digest = digest
        self.isSelected = isSelected
    }
}

public struct CharacterProfileSnapshot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let characterID: UUID
    public var characterName: String
    public var traits: [CharacterTrait]
    public var contradictions: [String]
    public var unspecified: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        characterID: UUID,
        characterName: String,
        traits: [CharacterTrait],
        contradictions: [String] = [],
        unspecified: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.characterID = characterID
        self.characterName = characterName
        self.traits = traits
        self.contradictions = contradictions
        self.unspecified = unspecified
        self.createdAt = createdAt
    }
}

public struct GenerationReference: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let artworkID: UUID
    public var preserveFace: Bool
    public var preserveClothing: Bool
    public var preserveComposition: Bool

    public init(
        id: UUID = UUID(),
        artworkID: UUID,
        preserveFace: Bool = false,
        preserveClothing: Bool = false,
        preserveComposition: Bool = false
    ) {
        self.id = id
        self.artworkID = artworkID
        self.preserveFace = preserveFace
        self.preserveClothing = preserveClothing
        self.preserveComposition = preserveComposition
    }
}

public struct Artwork: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let jobID: UUID
    public let characterID: UUID
    public var filename: String
    public var sha256: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var createdAt: Date
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        jobID: UUID,
        characterID: UUID,
        filename: String,
        sha256: String,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date = .now,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.jobID = jobID
        self.characterID = characterID
        self.filename = filename
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}

public struct ImportRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public var sourceFilename: String
    public var copiedFilename: String
    public var characterCount: Int
    public var chapterCount: Int
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        sourceFilename: String,
        copiedFilename: String,
        characterCount: Int,
        chapterCount: Int,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.sourceFilename = sourceFilename
        self.copiedFilename = copiedFilename
        self.characterCount = characterCount
        self.chapterCount = chapterCount
        self.completedAt = completedAt
    }
}

public struct CodexSessionRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let jobID: UUID?
    public var threadID: String
    public var turnID: String?
    public var codexVersion: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        jobID: UUID? = nil,
        threadID: String,
        turnID: String? = nil,
        codexVersion: String,
        startedAt: Date = .now,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.threadID = threadID
        self.turnID = turnID
        self.codexVersion = codexVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
