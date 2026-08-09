import Foundation

public enum GenerationState: String, Codable, CaseIterable, Sendable {
    case draft
    case queued
    case running
    case saving
    case succeeded
    case cancelled
    case failed
}

public enum GenerationTransitionError: Error, Equatable, Sendable {
    case invalidTransition(from: GenerationState, to: GenerationState)
    case artworkRequired
}

public struct GenerationJob: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let characterID: UUID
    public let profileSnapshotID: UUID
    public var state: GenerationState
    public var outputDirectoryName: String
    public var artworkID: UUID?
    public var diagnosticCode: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        characterID: UUID,
        profileSnapshotID: UUID,
        state: GenerationState = .draft,
        outputDirectoryName: String? = nil,
        artworkID: UUID? = nil,
        diagnosticCode: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.characterID = characterID
        self.profileSnapshotID = profileSnapshotID
        self.state = state
        self.outputDirectoryName = outputDirectoryName ?? id.uuidString.lowercased()
        self.artworkID = artworkID
        self.diagnosticCode = diagnosticCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func transition(to nextState: GenerationState, artworkID: UUID? = nil) throws {
        let allowed: Set<GenerationState>
        switch state {
        case .draft:
            allowed = [.queued]
        case .queued:
            allowed = [.running, .cancelled, .failed]
        case .running:
            allowed = [.saving, .cancelled, .failed]
        case .saving:
            allowed = [.succeeded, .cancelled, .failed]
        case .succeeded, .cancelled, .failed:
            allowed = []
        }

        guard allowed.contains(nextState) else {
            throw GenerationTransitionError.invalidTransition(from: state, to: nextState)
        }
        if nextState == .succeeded, artworkID == nil {
            throw GenerationTransitionError.artworkRequired
        }

        self.artworkID = artworkID ?? self.artworkID
        state = nextState
        updatedAt = .now
    }
}

public enum PortraitComposition: String, Codable, CaseIterable, Sendable {
    case portrait
    case waistUp
    case fullBody
    case scene
    case bookWorld
}

public enum IllustrationStyle: String, Codable, CaseIterable, Sendable {
    case cinematicRealism
    case classicBookIllustration
    case engraving
    case watercolor
    case graphicNovel
    case atmosphericPainting
    case neutralStudioPortrait
}

public struct GenerationSettings: Codable, Hashable, Sendable {
    public var composition: PortraitComposition
    public var style: IllustrationStyle
    public var aspectRatio: String
    public var lighting: String
    public var background: String
    public var mood: String
    public var strictToBook: Bool
    public var artisticAdditions: String

    public init(
        composition: PortraitComposition = .portrait,
        style: IllustrationStyle = .classicBookIllustration,
        aspectRatio: String = "4:5",
        lighting: String = "soft natural light",
        background: String = "a neutral background appropriate to the book era",
        mood: String = "restrained",
        strictToBook: Bool = true,
        artisticAdditions: String = ""
    ) {
        self.composition = composition
        self.style = style
        self.aspectRatio = aspectRatio
        self.lighting = lighting
        self.background = background
        self.mood = mood
        self.strictToBook = strictToBook
        self.artisticAdditions = artisticAdditions
    }
}
