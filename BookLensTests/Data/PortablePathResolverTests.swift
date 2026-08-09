import BookLensData
import Foundation
import XCTest

final class PortablePathResolverTests: XCTestCase {
    func testRepairsTransferredBookArtworkAndJobPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensPortablePathTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bookID = UUID()
        let artworkID = UUID()
        let jobID = UUID()
        let source = root
            .appendingPathComponent("Library/\(bookID.uuidString.lowercased())/Source", isDirectory: true)
            .appendingPathComponent("book.epub")
        let cover = root
            .appendingPathComponent("Library/\(bookID.uuidString.lowercased())/Cover", isDirectory: true)
            .appendingPathComponent("cover.jpg")
        let artwork = root
            .appendingPathComponent("Artworks", isDirectory: true)
            .appendingPathComponent("\(artworkID.uuidString.lowercased()).png")
        let output = root
            .appendingPathComponent("Jobs/\(jobID.uuidString.lowercased())/output", isDirectory: true)

        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("book".utf8).write(to: source)
        try Data("cover".utf8).write(to: cover)
        try Data("image".utf8).write(to: artwork)

        let resolver = PortablePathResolver(storageRoot: root)
        XCTAssertEqual(
            resolver.bookSourcePath(
                bookID: bookID,
                sourceFilename: "book.epub",
                currentPath: "/Users/other/Library/Application Support/BookLens/Library/book.epub"
            ),
            source.standardizedFileURL.path
        )
        XCTAssertEqual(
            resolver.bookCoverPath(
                bookID: bookID,
                currentPath: "/Users/other/Library/Application Support/BookLens/Library/cover.jpg"
            ),
            cover.standardizedFileURL.path
        )
        XCTAssertEqual(
            resolver.artworkPath(
                artworkID: artworkID,
                filename: artwork.lastPathComponent,
                currentPath: "/Users/other/Library/Application Support/BookLens/Artworks/\(artwork.lastPathComponent)"
            ),
            artwork.standardizedFileURL.path
        )
        XCTAssertEqual(
            resolver.jobOutputDirectoryPath(
                jobID: jobID,
                currentPath: "/Users/other/Library/Application Support/BookLens/Jobs/output"
            ),
            output.standardizedFileURL.path
        )
    }

    func testKeepsExistingPathsAndDoesNotGuessAmongMultipleBookFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensPortablePathTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bookID = UUID()
        let sourceDirectory = root
            .appendingPathComponent("Library/\(bookID.uuidString.lowercased())/Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let first = sourceDirectory.appendingPathComponent("first.epub")
        let second = sourceDirectory.appendingPathComponent("second.epub")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let resolver = PortablePathResolver(storageRoot: root)
        XCTAssertNil(
            resolver.bookSourcePath(
                bookID: bookID,
                sourceFilename: "missing.epub",
                currentPath: "/Users/other/missing.epub"
            )
        )
        XCTAssertNil(
            resolver.bookSourcePath(
                bookID: bookID,
                sourceFilename: first.lastPathComponent,
                currentPath: first.path
            )
        )
    }
}
