import Foundation
import SwiftData

@Model
public final class BookRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var author: String
    public var language: String?
    public var sourceFilename: String
    public var storedSourcePath: String
    public var processingStatus: String
    public var analysisStatus: String = "pending"
    public var synopsis: String = ""
    public var sourceKind: String = "local"
    public var sourceURL: String?
    public var coverPath: String = ""
    public var coverSource: String = "none"
    public var coverArtworkID: UUID?
    public var audience: String = "unspecified"
    public var ageMin: Int = 0
    public var ageMax: Int = 0
    public var genres: [String] = []
    public var classificationConfidence: String = "unspecified"
    public var importedAt: Date
    public var chapterCount: Int
    public var characterCount: Int

    @Relationship(deleteRule: .cascade, inverse: \ChapterRecord.book)
    public var chapters: [ChapterRecord]

    @Relationship(deleteRule: .cascade, inverse: \CharacterRecord.book)
    public var characters: [CharacterRecord]

    public init(
        id: UUID = UUID(),
        title: String,
        author: String,
        language: String? = nil,
        sourceFilename: String,
        storedSourcePath: String,
        processingStatus: String = "ready",
        analysisStatus: String = "pending",
        synopsis: String = "",
        sourceKind: String = "local",
        sourceURL: String? = nil,
        coverPath: String = "",
        coverSource: String = "none",
        coverArtworkID: UUID? = nil,
        audience: String = "unspecified",
        ageMin: Int = 0,
        ageMax: Int = 0,
        genres: [String] = [],
        classificationConfidence: String = "unspecified",
        importedAt: Date = .now,
        chapters: [ChapterRecord] = [],
        characters: [CharacterRecord] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.language = language
        self.sourceFilename = sourceFilename
        self.storedSourcePath = storedSourcePath
        self.processingStatus = processingStatus
        self.analysisStatus = analysisStatus
        self.synopsis = synopsis
        self.sourceKind = sourceKind
        self.sourceURL = sourceURL
        self.coverPath = coverPath
        self.coverSource = coverSource
        self.coverArtworkID = coverArtworkID
        self.audience = audience
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.genres = genres
        self.classificationConfidence = classificationConfidence
        self.importedAt = importedAt
        self.chapters = chapters
        self.characters = characters
        chapterCount = chapters.count
        characterCount = characters.count
    }
}

@Model
public final class ChapterRecord {
    @Attribute(.unique) public var id: UUID
    public var index: Int
    public var title: String
    public var text: String
    public var rangeStart: Int
    public var rangeEnd: Int
    public var book: BookRecord?

    @Relationship(deleteRule: .cascade, inverse: \EvidenceRecord.chapter)
    public var evidence: [EvidenceRecord]

    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        text: String,
        rangeStart: Int,
        rangeEnd: Int,
        evidence: [EvidenceRecord] = []
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.text = text
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.evidence = evidence
    }
}

@Model
public final class CharacterRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var aliases: [String]
    public var occurrenceCount: Int
    public var isExcluded: Bool
    public var isMainCharacter: Bool = false
    public var role: String = ""
    public var summary: String = ""
    public var origin: String = "local"
    public var book: BookRecord?

    @Relationship(deleteRule: .cascade, inverse: \TraitRecord.character)
    public var traits: [TraitRecord]

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        occurrenceCount: Int = 0,
        isExcluded: Bool = false,
        isMainCharacter: Bool = false,
        role: String = "",
        summary: String = "",
        origin: String = "local",
        traits: [TraitRecord] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.occurrenceCount = occurrenceCount
        self.isExcluded = isExcluded
        self.isMainCharacter = isMainCharacter
        self.role = role
        self.summary = summary
        self.origin = origin
        self.traits = traits
    }
}

@Model
public final class TraitRecord {
    @Attribute(.unique) public var id: UUID
    public var category: String
    public var value: String
    public var confidence: String
    public var evidenceIDs: [UUID]
    public var character: CharacterRecord?

    public init(
        id: UUID = UUID(),
        category: String,
        value: String,
        confidence: String,
        evidenceIDs: [UUID]
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.confidence = confidence
        self.evidenceIDs = evidenceIDs
    }
}

@Model
public final class EvidenceRecord {
    @Attribute(.unique) public var id: UUID
    public var characterName: String
    public var text: String
    public var rangeStart: Int
    public var rangeEnd: Int
    public var digest: String
    public var isSelected: Bool
    public var sourceURL: String?
    public var chapter: ChapterRecord?

    public init(
        id: UUID = UUID(),
        characterName: String,
        text: String,
        rangeStart: Int,
        rangeEnd: Int,
        digest: String,
        isSelected: Bool = true,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.characterName = characterName
        self.text = text
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.digest = digest
        self.isSelected = isSelected
        self.sourceURL = sourceURL
    }
}

@Model
public final class GenerationJobRecord {
    @Attribute(.unique) public var id: UUID
    public var characterID: UUID
    public var state: String
    public var outputDirectoryPath: String
    public var turnID: String?
    public var diagnosticCode: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        characterID: UUID,
        state: String,
        outputDirectoryPath: String,
        turnID: String? = nil,
        diagnosticCode: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.characterID = characterID
        self.state = state
        self.outputDirectoryPath = outputDirectoryPath
        self.turnID = turnID
        self.diagnosticCode = diagnosticCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class ArtworkRecord {
    @Attribute(.unique) public var id: UUID
    public var jobID: UUID
    public var characterID: UUID
    public var bookID: UUID
    public var filename: String
    public var storedPath: String
    public var sha256: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var style: String
    public var composition: String = ""
    public var createdAt: Date
    public var isFavorite: Bool
    public var isPrimary: Bool

    public init(
        id: UUID = UUID(),
        jobID: UUID,
        characterID: UUID,
        bookID: UUID,
        filename: String,
        storedPath: String,
        sha256: String,
        pixelWidth: Int,
        pixelHeight: Int,
        style: String,
        composition: String = "",
        createdAt: Date = .now,
        isFavorite: Bool = false,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.jobID = jobID
        self.characterID = characterID
        self.bookID = bookID
        self.filename = filename
        self.storedPath = storedPath
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.style = style
        self.composition = composition
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.isPrimary = isPrimary
    }
}
