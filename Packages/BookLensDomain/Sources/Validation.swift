import Foundation

public enum CharacterProfileValidationError: Error, Equatable, Sendable {
    case evidenceMissing(traitID: UUID)
    case evidenceUnknown(traitID: UUID, evidenceID: UUID)
}

public struct CharacterProfileValidator: Sendable {
    public init() {}

    public func validate(
        traits: [CharacterTrait],
        availableEvidenceIDs: Set<UUID>
    ) throws {
        for trait in traits where trait.confidence == .confirmed || trait.confidence == .probable {
            guard !trait.evidenceIDs.isEmpty else {
                throw CharacterProfileValidationError.evidenceMissing(traitID: trait.id)
            }
            for evidenceID in trait.evidenceIDs where !availableEvidenceIDs.contains(evidenceID) {
                throw CharacterProfileValidationError.evidenceUnknown(
                    traitID: trait.id,
                    evidenceID: evidenceID
                )
            }
        }
    }
}
