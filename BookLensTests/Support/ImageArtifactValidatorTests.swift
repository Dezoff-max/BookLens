import BookLensSupport
import Foundation
import XCTest

final class ImageArtifactValidatorTests: XCTestCase {
    func testValidatesPNGAndComputesDigest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensImageTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let imageURL = root.appendingPathComponent("result.png")
        try png.write(to: imageURL)

        let result = try ImageArtifactValidator().validate(imageURL, inside: root)
        XCTAssertEqual(result.pixelWidth, 1)
        XCTAssertEqual(result.pixelHeight, 1)
        XCTAssertEqual(result.sha256.count, 64)
    }
}
