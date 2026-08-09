import BookLensCodex
import BookLensDomain
import XCTest

final class PromptBuilderTests: XCTestCase {
    func testPromptIsDeterministicAndContainsOutputBoundary() throws {
        let evidenceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let profile = CharacterProfileSnapshot(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            characterID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            characterName: "Character",
            traits: [
                CharacterTrait(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    category: "eyes",
                    value: "gray",
                    confidence: .confirmed,
                    evidenceIDs: [evidenceID]
                )
            ]
        )
        let output = URL(fileURLWithPath: "/tmp/booklens-job/output")
        let first = try PromptBuilder().build(
            profile: profile,
            availableEvidenceIDs: [evidenceID],
            settings: GenerationSettings(),
            references: [],
            outputDirectory: output
        )
        let second = try PromptBuilder().build(
            profile: profile,
            availableEvidenceIDs: [evidenceID],
            settings: GenerationSettings(),
            references: [],
            outputDirectory: output
        )
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("/tmp/booklens-job/output"))
        XCTAssertTrue(first.contains("evidence:"))
        XCTAssertTrue(first.contains("2K HDR"))
        XCTAssertTrue(first.contains("2560 × 1440 px"))
        XCTAssertTrue(first.contains("not a thumbnail, preview, or reduced copy"))
        XCTAssertTrue(first.contains("Always keep the selected character's entire head inside the frame"))
        XCTAssertTrue(first.contains("Never create a headless figure"))
        XCTAssertTrue(first.contains("A credible book-world environment is required"))
        XCTAssertTrue(first.contains("at least 3–5 distinct period or occupation-specific objects"))
        XCTAssertTrue(first.contains("do not replace uncertainty with an empty photo studio"))
        XCTAssertTrue(first.contains("do not apply the same warm orange grading to every book"))
        XCTAssertTrue(first.contains("a readable book-world interior or location"))
    }

    func testBookWorldPromptContainsEnsembleAndRecognizableBookContext() throws {
        let profile = CharacterProfileSnapshot(
            characterID: UUID(),
            characterName: "Winston",
            traits: [
                CharacterTrait(
                    category: "age",
                    value: "about forty years old",
                    confidence: .unspecified
                )
            ]
        )
        let prompt = try PromptBuilder().build(
            profile: profile,
            availableEvidenceIDs: [],
            bookContext: BookPromptContext(
                title: "1984",
                author: "George Orwell",
                synopsis: "Totalitarian Oceania and the Ministry of Truth.",
                importantCharacters: ["Winston — protagonist", "Julia — ally"]
            ),
            settings: GenerationSettings(
                composition: .bookWorld,
                style: .cinematicRealism,
                aspectRatio: "16:9"
            ),
            references: [],
            outputDirectory: URL(fileURLWithPath: "/tmp/booklens-world/output")
        )

        XCTAssertTrue(prompt.contains("one cohesive wide illustration of the literary world"))
        XCTAssertTrue(prompt.contains("1984"))
        XCTAssertTrue(prompt.contains("Julia — ally"))
        XCTAssertTrue(prompt.contains("2–4 other important characters"))
        XCTAssertTrue(prompt.contains("wide 16:9 composition"))
        XCTAssertTrue(prompt.contains("every key character's head and face"))
        XCTAssertTrue(prompt.contains("architecture, wall finishes, windows, doors, flooring, furniture, textiles"))
    }
}
