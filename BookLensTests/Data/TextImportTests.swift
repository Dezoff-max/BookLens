import AppKit
import BookLensData
import BookLensSupport
import Foundation
import XCTest

final class TextImportTests: XCTestCase {
    func testTXTNormalizationAndChapterSplit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensTXTTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("book.txt")
        try "Глава 1\r\n\r\nАнна вошла. Анна сказала: привет.\r\n\r\nГлава 2\r\nБорис ответил Анне.".write(to: source, atomically: true, encoding: .utf8)

        let extracted = try await TXTExtractor().extract(from: source)
        XCTAssertEqual(extracted.chapters.count, 2)
        XCTAssertFalse(extracted.chapters[0].text.contains("\r"))
    }

    func testTXTRejectsExcessiveExtractedText() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensTXTLimitTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("book.txt")
        try String(repeating: "А", count: 101).write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try await TXTExtractor(maximumSourceBytes: 1_024, maximumTextCharacters: 100).extract(from: source)
            XCTFail("Expected extracted text limit")
        } catch {
            XCTAssertEqual(error as? BookLensError, .extractedTextTooLarge(limitCharacters: 100))
        }
    }

    func testPipelineRejectsEmptyFileBeforeCopying() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensPipelineLimitTest-\(UUID().uuidString)", isDirectory: true)
        let storageRoot = root.appendingPathComponent("Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("empty.txt")
        try Data().write(to: source)

        let pipeline = BookImportPipeline(storage: try FileStorage(rootURL: storageRoot))
        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.importBook(from: source) { _ in }
        }
        let library = storageRoot.appendingPathComponent("Library", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []
        XCTAssertTrue(contents.isEmpty)
    }

    func testPDFWithoutTextLayerHasTypedError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensPDFTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let emptyPDF = root.appendingPathComponent("empty.pdf")
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: emptyPDF)

        do {
            _ = try await PDFTextExtractor().extract(from: emptyPDF)
            XCTFail("Expected a typed import failure")
        } catch {
            XCTAssertTrue(error is BookLensError)
        }
    }

    func testPipelineCopiesOriginalWithoutChangingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensPipelineTest-\(UUID().uuidString)", isDirectory: true)
        let storageRoot = root.appendingPathComponent("Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let original = "Глава 1\nАнна встретила Бориса. Анна улыбнулась Борису."
        try original.write(to: source, atomically: true, encoding: .utf8)

        let storage = try FileStorage(rootURL: storageRoot)
        let pipeline = BookImportPipeline(storage: storage)
        let imported = try await pipeline.importBook(from: source) { _ in }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertNotEqual(imported.storedSourceURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.storedSourceURL.path))
    }

    func testValidEPUBFollowsContainerAndSpine() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensEPUBTest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Package", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("META-INF", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("OEBPS", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        <?xml version="1.0"?>
        <container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
        """.write(
            to: package.appendingPathComponent("META-INF/container.xml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        <?xml version="1.0"?>
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata><dc:title>Fixture Book</dc:title><dc:creator>Fixture Author</dc:creator></metadata>
          <manifest><item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """.write(
            to: package.appendingPathComponent("OEBPS/content.opf"),
            atomically: true,
            encoding: .utf8
        )
        try "<html><head><title>Глава 1</title></head><body><p>Анна вошла в комнату.</p></body></html>".write(
            to: package.appendingPathComponent("OEBPS/chapter1.xhtml"),
            atomically: true,
            encoding: .utf8
        )
        let archive = root.appendingPathComponent("fixture.epub")
        try createZip(from: package, at: archive)

        let extracted = try await EPUBExtractor().extract(from: archive)
        XCTAssertEqual(extracted.title, "Fixture Book")
        XCTAssertEqual(extracted.author, "Fixture Author")
        XCTAssertEqual(extracted.chapters.count, 1)
        XCTAssertTrue(extracted.chapters[0].text.contains("Анна"))
    }

    func testPipelinePrefersEPUBMetadataAndNormalizesWhitespace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensEPUBMetadataTest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Package", isDirectory: true)
        let storageRoot = root.appendingPathComponent("Storage", isDirectory: true)
        try makeEPUBPackage(at: package, title: "Proper Book Title", author: "Fixture   Author")
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appendingPathComponent("book-title-as-url-slug.epub")
        try createZip(from: package, at: archive)
        let pipeline = BookImportPipeline(storage: try FileStorage(rootURL: storageRoot))

        let imported = try await pipeline.importBook(from: archive) { _ in }

        XCTAssertEqual(imported.book.title, "Proper Book Title")
        XCTAssertEqual(imported.book.author, "Fixture Author")
        XCTAssertEqual(imported.coverSource, "epub")
        XCTAssertNotNil(imported.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.coverURL?.path ?? ""))
    }

    func testAppleBooksLocatorFindsPersonalPDFAndMarksStoreDRM() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensAppleBooksTest-\(UUID().uuidString)", isDirectory: true)
        let personal = root.appendingPathComponent("iCloudBooks", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("%PDF-1.4\n%%EOF".utf8).write(to: personal.appendingPathComponent("Личная книга.pdf"))
        let protectedEPUB = downloads.appendingPathComponent("123.epub", isDirectory: true)
        try FileManager.default.createDirectory(
            at: protectedEPUB.appendingPathComponent("META-INF", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "<fairplay:sinf/>".write(
            to: protectedEPUB.appendingPathComponent("META-INF/sinf.xml"),
            atomically: true,
            encoding: .utf8
        )

        let locator = AppleBooksLibraryLocator(folders: [
            .init(url: personal, source: .iCloudBooks),
            .init(url: downloads, source: .downloadedStoreBook),
        ])
        let assets = locator.scan()

        XCTAssertEqual(assets.count, 2)
        XCTAssertEqual(assets.first(where: { $0.kind == .pdf })?.availability, .importable)
        XCTAssertEqual(assets.first(where: { $0.kind == .epub })?.availability, .drmProtected)
    }

    func testDirectoryEPUBCanBeExtracted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDirectoryEPUBTest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Personal.epub", isDirectory: true)
        try makeEPUBPackage(at: package)
        defer { try? FileManager.default.removeItem(at: root) }

        let extracted = try await EPUBExtractor().extract(from: package)

        XCTAssertEqual(extracted.title, "Fixture Book")
        XCTAssertEqual(extracted.chapters.count, 1)
    }

    func testPipelinePreservesDirectoryEPUBSupportWithinLimits() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDirectoryPipelineTest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Personal.epub", isDirectory: true)
        let storageRoot = root.appendingPathComponent("Storage", isDirectory: true)
        try makeEPUBPackage(at: package)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = BookImportPipeline(storage: try FileStorage(rootURL: storageRoot))
        let imported = try await pipeline.importBook(from: package) { _ in }

        XCTAssertEqual(imported.book.title, "Fixture Book")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.storedSourceURL.path))
    }

    func testAppleDRMEPUBHasTypedError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDRMEPUBTest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Protected.epub", isDirectory: true)
        try makeEPUBPackage(at: package)
        try "<fairplay:sinf/>".write(
            to: package.appendingPathComponent("META-INF/sinf.xml"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try await EPUBExtractor().extract(from: package)
            XCTFail("Expected Apple DRM to be rejected")
        } catch {
            XCTAssertEqual(error as? BookLensError, .drmProtectedBook)
        }
    }

    func testManualCyrillicNameFindsRealContext() {
        let chapters = [
            ExtractedChapter(
                title: "Глава 1",
                text: "Анна вошла в комнату. Затем анна открыла окно. Аннабель осталась в саду."
            ),
            ExtractedChapter(
                title: "Глава 2",
                text: "Борис позвал Анну, но Анна не ответила."
            ),
        ]

        let result = CharacterMentionFinder().find(name: "Анна", in: chapters)

        XCTAssertEqual(result.occurrenceCount, 3)
        XCTAssertEqual(result.evidence.count, 3)
        XCTAssertTrue(result.evidence.allSatisfy { $0.excerpt.localizedCaseInsensitiveContains("анна") })
    }

    private func createZip(from directory: URL, at archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", archive.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeEPUBPackage(
        at package: URL,
        title: String = "Fixture Book",
        author: String = "Fixture Author"
    ) throws {
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("META-INF", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("OEBPS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        <?xml version="1.0"?>
        <container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
        """.write(
            to: package.appendingPathComponent("META-INF/container.xml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        <?xml version="1.0"?>
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata><dc:title>\(title)</dc:title><dc:creator>\(author)</dc:creator></metadata>
          <manifest>
            <item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """.write(
            to: package.appendingPathComponent("OEBPS/content.opf"),
            atomically: true,
            encoding: .utf8
        )
        try "<html><head><title>Глава 1</title></head><body><p>Анна вошла.</p></body></html>".write(
            to: package.appendingPathComponent("OEBPS/chapter1.xhtml"),
            atomically: true,
            encoding: .utf8
        )
        try makeFixtureCover().write(to: package.appendingPathComponent("OEBPS/cover.jpg"))
    }

    private func makeFixtureCover() throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 450,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.22, green: 0.10, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 450)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch { }
}
