@testable import BookLensCodex
import BookLensSupport
import XCTest

final class BookAnalysisTests: XCTestCase {
    func testDecodesStructuredBookAnalysis() throws {
        let json = #"""
        {
          "bookTitle": "1984",
          "author": "George Orwell",
          "synopsis": "A novel about a totalitarian state.",
          "audience": "adult",
          "ageMin": 16,
          "ageMax": 99,
          "genres": ["Dystopia", "Political fiction"],
          "classificationConfidence": "high",
          "characters": [
            {
              "name": "Winston Smith",
              "role": "Protagonist",
              "description": "A Ministry of Truth employee who begins to resist the Party.",
              "aliases": ["Winston"],
              "traits": [
                {"category": "Build", "value": "Frail", "confidence": "confirmed"}
              ],
              "evidence": ["a smallish, frail figure"]
            }
          ],
          "sources": []
        }
        """#

        let result = try BookAnalysisService.decode(json)

        XCTAssertEqual(result.bookTitle, "1984")
        XCTAssertEqual(result.audience, "adult")
        XCTAssertEqual(result.ageMin, 16)
        XCTAssertEqual(result.genres ?? [], ["Dystopia", "Political fiction"])
        XCTAssertEqual(result.characters.map(\.name), ["Winston Smith"])
        XCTAssertEqual(result.characters[0].traits[0].confidence, "confirmed")
    }

    func testRejectsAnalysisWithoutCharacters() {
        let json = #"{"bookTitle":"1984","author":"George Orwell","synopsis":"","characters":[],"sources":[]}"#

        XCTAssertThrowsError(try BookAnalysisService.decode(json)) { error in
            XCTAssertEqual(error as? BookLensError, .invalidStructuredOutput)
        }
    }

    func testRepresentativeExcerptUsesMultipleChaptersAndHonorsLimit() {
        let chapters = [
            BookAnalysisChapter(title: "One", text: String(repeating: "A", count: 80)),
            BookAnalysisChapter(title: "Two", text: String(repeating: "B", count: 80)),
        ]

        let excerpt = BookAnalysisService.makeRepresentativeExcerpt(from: chapters, characterLimit: 100)

        XCTAssertTrue(excerpt.contains("## One"))
        XCTAssertTrue(excerpt.contains("## Two"))
        XCTAssertLessThanOrEqual(excerpt.filter { $0 == "A" || $0 == "B" }.count, 100)
    }

    func testRepresentativeExcerptSamplesBeginningMiddleAndEnd() {
        let text = String(repeating: "A", count: 100)
            + String(repeating: "M", count: 100)
            + String(repeating: "Z", count: 100)
        let excerpt = BookAnalysisService.makeRepresentativeExcerpt(
            from: [BookAnalysisChapter(title: "Long", text: text)],
            characterLimit: 90
        )

        XCTAssertTrue(excerpt.contains("A"))
        XCTAssertTrue(excerpt.contains("M"))
        XCTAssertTrue(excerpt.contains("Z"))
        XCTAssertLessThanOrEqual(excerpt.filter { "AMZ".contains($0) }.count, 90)
    }

    func testRepresentativeExcerptIncludesLastChapterInLargeBook() {
        let chapters = (0..<20).map {
            BookAnalysisChapter(title: "Chapter \($0)", text: String(repeating: "X", count: 5_000))
        }

        let excerpt = BookAnalysisService.makeRepresentativeExcerpt(from: chapters, characterLimit: 12_000)

        XCTAssertTrue(excerpt.contains("## Chapter 0"))
        XCTAssertTrue(excerpt.contains("## Chapter 19"))
    }

    func testBookAnalysisCapsExpensiveReasoningAtMedium() {
        XCTAssertEqual(BookAnalysisService.optimizedReasoningEffort("low"), "low")
        XCTAssertEqual(BookAnalysisService.optimizedReasoningEffort("medium"), "medium")
        XCTAssertEqual(BookAnalysisService.optimizedReasoningEffort("high"), "medium")
        XCTAssertEqual(BookAnalysisService.optimizedReasoningEffort("ultra"), "medium")
    }

    func testLocalBookAnalysisRejectsToolItemTypes() {
        XCTAssertTrue(CodexTurnRunner.isToolItem("commandExecution"))
        XCTAssertTrue(CodexTurnRunner.isToolItem("mcpToolCall"))
        XCTAssertTrue(CodexTurnRunner.isToolItem("webSearch"))
        XCTAssertFalse(CodexTurnRunner.isToolItem("agentMessage"))
        XCTAssertFalse(CodexTurnRunner.isToolItem("reasoning"))
    }

    func testLocalBookAnalysisDisablesBuiltInToolFamilies() {
        let features = CodexTurnRunner.toolFreeConfig["features"]?.objectValue
        XCTAssertEqual(features?["shell_tool"]?.boolValue, false)
        XCTAssertEqual(features?["unified_exec"]?.boolValue, false)
        XCTAssertEqual(features?["browser_use"]?.boolValue, false)
        XCTAssertEqual(features?["computer_use"]?.boolValue, false)
        XCTAssertEqual(features?["image_generation"]?.boolValue, false)
        XCTAssertEqual(features?["apps"]?.boolValue, false)
    }
}
