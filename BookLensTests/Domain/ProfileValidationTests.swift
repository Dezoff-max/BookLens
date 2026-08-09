import BookLensDomain
import XCTest

final class ProfileValidationTests: XCTestCase {
    func testConfirmedTraitMustBindKnownEvidence() throws {
        let evidenceID = UUID()
        let valid = CharacterTrait(
            category: "eyes",
            value: "серые",
            confidence: .confirmed,
            evidenceIDs: [evidenceID]
        )
        XCTAssertNoThrow(
            try CharacterProfileValidator().validate(
                traits: [valid],
                availableEvidenceIDs: [evidenceID]
            )
        )

        let invalid = CharacterTrait(
            category: "hair",
            value: "тёмные",
            confidence: .confirmed
        )
        XCTAssertThrowsError(
            try CharacterProfileValidator().validate(
                traits: [invalid],
                availableEvidenceIDs: []
            )
        )
    }
}
