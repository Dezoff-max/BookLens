import BookLensDomain
import XCTest

final class GenerationStateMachineTests: XCTestCase {
    func testSucceededRequiresArtworkAndValidPath() throws {
        var job = GenerationJob(characterID: UUID(), profileSnapshotID: UUID())
        try job.transition(to: .queued)
        try job.transition(to: .running)
        try job.transition(to: .saving)

        XCTAssertThrowsError(try job.transition(to: .succeeded)) { error in
            XCTAssertEqual(error as? GenerationTransitionError, .artworkRequired)
        }

        let artworkID = UUID()
        try job.transition(to: .succeeded, artworkID: artworkID)
        XCTAssertEqual(job.state, .succeeded)
        XCTAssertEqual(job.artworkID, artworkID)
    }

    func testLateSuccessAfterCancellationIsRejected() throws {
        var job = GenerationJob(characterID: UUID(), profileSnapshotID: UUID())
        try job.transition(to: .queued)
        try job.transition(to: .running)
        try job.transition(to: .cancelled)

        XCTAssertThrowsError(try job.transition(to: .succeeded, artworkID: UUID()))
        XCTAssertEqual(job.state, .cancelled)
    }
}
