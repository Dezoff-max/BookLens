import BookLensSupport
import Foundation
import UniformTypeIdentifiers

public struct EPUBExtractor: BookTextExtractor {
    private let maximumArchiveBytes: Int
    private let maximumExpandedBytes: Int
    private let maximumEntries: Int
    private let maximumTextCharacters: Int

    public init(
        maximumArchiveBytes: Int = 100 * 1_024 * 1_024,
        maximumExpandedBytes: Int = 300 * 1_024 * 1_024,
        maximumEntries: Int = 20_000,
        maximumTextCharacters: Int = 2_000_000
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumEntries = maximumEntries
        self.maximumTextCharacters = maximumTextCharacters
    }

    public func supports(_ type: UTType) -> Bool {
        type.identifier == "org.idpf.epub-container"
            || type.preferredFilenameExtension?.lowercased() == "epub"
    }

    public func extract(from url: URL) async throws -> ExtractedBook {
        try Task.checkCancellation()
        let sourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if sourceValues.isDirectory == true {
            try validatePackageDirectory(at: url)
            try rejectAppleDRM(in: url)
            return try extractPackage(at: url)
        }

        let size = sourceValues.fileSize ?? 0
        guard size > 0, size <= maximumArchiveBytes else {
            throw BookLensError.unsupportedBook
        }

        let entries = try await listEntries(in: url)
        guard !entries.isEmpty, entries.count <= maximumEntries else {
            throw BookLensError.unsupportedBook
        }
        var expandedBytes = 0
        for entry in entries {
            guard isSafeArchivePath(entry.path) else {
                throw BookLensError.invalidOutputPath
            }
            expandedBytes += entry.uncompressedBytes
            guard expandedBytes <= maximumExpandedBytes else {
                throw BookLensError.unsupportedBook
            }
        }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLens-EPUB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        _ = try await runUnzip(arguments: ["-qq", url.path, "-d", temporaryRoot.path])
        try Task.checkCancellation()

        try rejectAppleDRM(in: temporaryRoot)
        return try extractPackage(at: temporaryRoot)
    }

    private func extractPackage(at packageRoot: URL) throws -> ExtractedBook {
        let containerURL = packageRoot.appendingPathComponent("META-INF/container.xml")
        guard let containerParser = XMLParser(contentsOf: containerURL) else {
            throw BookLensError.unsupportedBook
        }
        let containerDelegate = ContainerXMLDelegate()
        containerParser.delegate = containerDelegate
        guard containerParser.parse(), let opfPath = containerDelegate.opfPath,
              isSafeArchivePath(opfPath)
        else {
            throw BookLensError.unsupportedBook
        }

        let opfURL = packageRoot.appendingPathComponent(opfPath).standardizedFileURL
        try ensure(opfURL, isInside: packageRoot)
        guard let opfParser = XMLParser(contentsOf: opfURL) else {
            throw BookLensError.unsupportedBook
        }
        let opfDelegate = OPFXMLDelegate()
        opfParser.delegate = opfDelegate
        guard opfParser.parse() else {
            throw BookLensError.unsupportedBook
        }

        let baseURL = opfURL.deletingLastPathComponent()
        var chapters: [ExtractedChapter] = []
        var extractedCharacterCount = 0
        for itemID in opfDelegate.spine {
            try Task.checkCancellation()
            guard let href = opfDelegate.manifest[itemID], isSafeArchivePath(href) else { continue }
            let chapterURL = baseURL.appendingPathComponent(href).standardizedFileURL
            try ensure(chapterURL, isInside: packageRoot)
            guard let parser = XMLParser(contentsOf: chapterURL) else { continue }
            let textDelegate = XHTMLTextDelegate()
            parser.delegate = textDelegate
            guard parser.parse() else { continue }
            let normalized = TextNormalizer().normalize(textDelegate.text)
            guard !normalized.isEmpty else { continue }
            extractedCharacterCount += normalized.count
            guard extractedCharacterCount <= maximumTextCharacters else {
                throw BookLensError.extractedTextTooLarge(limitCharacters: maximumTextCharacters)
            }
            let title = textDelegate.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(
                ExtractedChapter(
                    title: title?.isEmpty == false ? title! : "Section \(chapters.count + 1)",
                    text: normalized
                )
            )
        }

        guard !chapters.isEmpty else {
            throw BookLensError.unsupportedBook
        }
        return ExtractedBook(
            title: opfDelegate.title,
            author: opfDelegate.author,
            language: opfDelegate.language,
            chapters: chapters
        )
    }

    private func validatePackageDirectory(at root: URL) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in false }
        ) else {
            throw BookLensError.unsupportedBook
        }

        var entryCount = 0
        var expandedBytes = 0
        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            entryCount += 1
            guard entryCount <= maximumEntries else { throw BookLensError.unsupportedBook }
            try ensure(item.standardizedFileURL, isInside: root)
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw BookLensError.invalidOutputPath }
            if values.isRegularFile == true {
                expandedBytes += values.fileSize ?? 0
                guard expandedBytes <= maximumExpandedBytes else { throw BookLensError.unsupportedBook }
            }
        }
        guard entryCount > 0 else { throw BookLensError.unsupportedBook }
    }

    private func rejectAppleDRM(in root: URL) throws {
        let metadata = root.appendingPathComponent("META-INF", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.appendingPathComponent("sinf.xml").path) {
            throw BookLensError.drmProtectedBook
        }
        let encryptionURL = metadata.appendingPathComponent("encryption.xml")
        guard let size = try? encryptionURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2 * 1_024 * 1_024,
              let data = try? Data(contentsOf: encryptionURL, options: [.mappedIfSafe])
        else {
            return
        }
        if String(decoding: data, as: UTF8.self)
            .localizedCaseInsensitiveContains("http://itunes.apple.com/dataenc") {
            throw BookLensError.drmProtectedBook
        }
    }

    private func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry] {
        let namesOutput = try await runUnzip(arguments: ["-Z1", archiveURL.path])
        let names = namesOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let listing = try await runUnzip(arguments: ["-l", archiveURL.path])
        let lengths = listing.split(separator: "\n").compactMap { line -> Int? in
            let fields = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count >= 4 else { return nil }
            return Int(fields[0])
        }
        return names.enumerated().map { index, path in
            ArchiveEntry(path: path, uncompressedBytes: index < lengths.count ? lengths[index] : 0)
        }
    }

    private func runUnzip(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let outputGroup = DispatchGroup()
                let stdoutResult = ProcessOutputResult()
                let stderrResult = ProcessOutputResult()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        stdoutResult.capture {
                            try Self.readBounded(stdout.fileHandleForReading, maximumBytes: 8 * 1_024 * 1_024)
                        }
                        outputGroup.leave()
                    }
                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        stderrResult.capture {
                            try Self.readBounded(stderr.fileHandleForReading, maximumBytes: 1 * 1_024 * 1_024)
                        }
                        outputGroup.leave()
                    }

                    let deadline = Date.now.addingTimeInterval(30)
                    while process.isRunning, Date.now < deadline {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                    if process.isRunning {
                        process.terminate()
                        process.waitUntilExit()
                        outputGroup.wait()
                        throw BookLensError.timeout(operation: "unzip")
                    }
                    outputGroup.wait()
                    let data = try stdoutResult.value()
                    _ = try stderrResult.value()
                    guard process.terminationStatus == 0 else {
                        throw BookLensError.unsupportedBook
                    }
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func readBounded(_ handle: FileHandle, maximumBytes: Int) throws -> Data {
        var result = Data()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            guard result.count <= maximumBytes - chunk.count else {
                throw BookLensError.unsupportedBook
            }
            result.append(chunk)
        }
        return result
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && !components.contains("..") && !components.contains("")
    }

    private func ensure(_ candidate: URL, isInside root: URL) throws {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard candidate.resolvingSymlinksInPath().path.hasPrefix(rootPath) else {
            throw BookLensError.invalidOutputPath
        }
    }
}

private final class ProcessOutputResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?

    func capture(_ operation: () throws -> Data) {
        let captured = Result { try operation() }
        lock.lock()
        result = captured
        lock.unlock()
    }

    func value() throws -> Data {
        lock.lock()
        let captured = result
        lock.unlock()
        guard let captured else { throw BookLensError.unsupportedBook }
        return try captured.get()
    }
}

private struct ArchiveEntry: Sendable {
    let path: String
    let uncompressedBytes: Int
}

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.hasSuffix("rootfile"), let path = attributeDict["full-path"] {
            opfPath = path
        }
    }
}

private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var language: String?
    var manifest: [String: String] = [:]
    var spine: [String] = []
    private var activeMetadataElement: String?
    private var textBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if ["title", "creator", "language"].contains(localName) {
            activeMetadataElement = localName
            textBuffer = ""
        } else if localName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest[id] = href.removingPercentEncoding ?? href
        } else if localName == "itemref", let idref = attributeDict["idref"] {
            spine.append(idref)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeMetadataElement != nil { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == activeMetadataElement else { return }
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if localName == "title", title == nil { title = value }
        if localName == "creator", author == nil { author = value }
        if localName == "language", language == nil { language = value }
        activeMetadataElement = nil
        textBuffer = ""
    }
}

private final class XHTMLTextDelegate: NSObject, XMLParserDelegate {
    var text = ""
    var title: String?
    private var isInsideTitle = false
    private var titleBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "title" || localName == "h1" {
            isInsideTitle = true
            titleBuffer = ""
        }
        if ["p", "div", "h1", "h2", "h3", "li", "br"].contains(localName), !text.hasSuffix("\n") {
            text.append("\n")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text.append(string)
        if isInsideTitle { titleBuffer.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "title" || localName == "h1" {
            if title == nil { title = titleBuffer }
            isInsideTitle = false
        }
        if ["p", "div", "h1", "h2", "h3", "li"].contains(localName), !text.hasSuffix("\n") {
            text.append("\n")
        }
    }
}
