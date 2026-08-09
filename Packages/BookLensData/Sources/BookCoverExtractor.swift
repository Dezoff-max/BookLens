@preconcurrency import AppKit
import BookLensSupport
import Foundation
import ImageIO
@preconcurrency import PDFKit

public struct ExtractedBookCover: Sendable {
    public let data: Data
    public let fileExtension: String
    public let source: String

    public init(data: Data, fileExtension: String, source: String) {
        self.data = data
        self.fileExtension = fileExtension
        self.source = source
    }
}

public actor BookCoverExtractor {
    private let maximumImageBytes = 60 * 1_024 * 1_024
    private let supportedExtensions = Set(["jpg", "jpeg", "png", "webp"])

    public init() {}

    public func extractCover(from sourceURL: URL) async throws -> ExtractedBookCover? {
        switch sourceURL.pathExtension.lowercased() {
        case "epub":
            return try extractEPUBCover(from: sourceURL)
        case "pdf":
            return extractPDFCover(from: sourceURL)
        default:
            return nil
        }
    }

    private func extractEPUBCover(from sourceURL: URL) throws -> ExtractedBookCover? {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            return try extractCoverFromDirectory(sourceURL)
        }

        let listing = try runUnzip(arguments: ["-Z1", sourceURL.path])
        let entries = String(decoding: listing, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter(isSafeArchivePath)

        for path in rankedImagePaths(entries) {
            let data = try runUnzip(arguments: ["-p", sourceURL.path, path])
            if isUsableImage(data) {
                return ExtractedBookCover(
                    data: data,
                    fileExtension: normalizedExtension(path),
                    source: "epub"
                )
            }
        }
        return nil
    }

    private func extractCoverFromDirectory(_ root: URL) throws -> ExtractedBookCover? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var candidates: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard url.resolvingSymlinksInPath().path.hasPrefix(rootPath) else {
                throw BookLensError.invalidOutputPath
            }
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                candidates.append(url)
            }
        }

        let ranked = candidates.sorted { coverScore($0.path) > coverScore($1.path) }
        for url in ranked {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if isUsableImage(data) {
                return ExtractedBookCover(
                    data: data,
                    fileExtension: normalizedExtension(url.path),
                    source: "epub"
                )
            }
        }
        return nil
    }

    private func extractPDFCover(from sourceURL: URL) -> ExtractedBookCover? {
        guard let document = PDFDocument(url: sourceURL),
              let firstPage = document.page(at: 0)
        else { return nil }

        let bounds = firstPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let targetHeight: CGFloat = 1_800
        let targetWidth = max(600, min(1_800, targetHeight * bounds.width / bounds.height))
        let image = firstPage.thumbnail(
            of: NSSize(width: targetWidth, height: targetHeight),
            for: .mediaBox
        )
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]),
              isUsableImage(data)
        else { return nil }
        return ExtractedBookCover(data: data, fileExtension: "png", source: "pdf")
    }

    private func rankedImagePaths(_ paths: [String]) -> [String] {
        paths
            .filter { supportedExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .sorted { coverScore($0) > coverScore($1) }
    }

    private func coverScore(_ path: String) -> Int {
        let lower = path.lowercased()
        let name = URL(fileURLWithPath: lower).deletingPathExtension().lastPathComponent
        var score = 0
        if name == "cover" { score += 1_000 }
        if name.hasPrefix("cover") { score += 500 }
        if lower.contains("cover") { score += 250 }
        if lower.contains("title") || lower.contains("front") { score += 100 }
        if lower.contains("image") || lower.contains("media") { score += 20 }
        if lower.contains("icon") || lower.contains("logo") || lower.contains("thumb") { score -= 300 }
        return score
    }

    private func isUsableImage(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        // Older and independently produced EPUB files often ship a legitimate
        // 200–220 px-wide cover. Keep a conservative floor, but do not reject
        // those real covers solely because they predate Retina artwork.
        return width >= 120 && height >= 160
    }

    private func normalizedExtension(_ path: String) -> String {
        let value = URL(fileURLWithPath: path).pathExtension.lowercased()
        return value == "jpeg" ? "jpg" : value
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && !components.contains("..") && !components.contains("")
    }

    private func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BookLensError.unsupportedBook
        }
        return data
    }
}
