import BookLensCodex
import Foundation
import XCTest

final class LineFramerTests: XCTestCase {
    func testFramesPartialStdoutChunks() throws {
        var framer = LineFramer()
        let firstChunk = #"{"id":1,"res"#
        let secondChunk = #"ult":{}}"# + "\n" + #"{"id":2}"# + "\r\n"
        XCTAssertTrue(try framer.append(Data(firstChunk.utf8)).isEmpty)
        let lines = try framer.append(Data(secondChunk.utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(decoding: lines[0], as: UTF8.self), #"{"id":1,"result":{}}"#)
        XCTAssertEqual(String(decoding: lines[1], as: UTF8.self), #"{"id":2}"#)
    }

    func testRejectsOversizedUnterminatedFrame() throws {
        var framer = LineFramer(maximumLineLength: 8)
        XCTAssertThrowsError(try framer.append(Data(repeating: 0x61, count: 9)))
    }

    func testRejectsOversizedCompletedFrame() throws {
        var framer = LineFramer(maximumLineLength: 8)
        var data = Data(repeating: 0x61, count: 9)
        data.append(0x0A)
        XCTAssertThrowsError(try framer.append(data))
    }

    func testAcceptsFrameExactlyAtLimit() throws {
        var framer = LineFramer(maximumLineLength: 8)
        var data = Data(repeating: 0x61, count: 8)
        data.append(0x0A)
        XCTAssertEqual(try framer.append(data).first?.count, 8)
    }
}
