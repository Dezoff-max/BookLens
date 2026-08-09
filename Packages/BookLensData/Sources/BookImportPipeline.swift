import BookLensDomain
import BookLensSupport
import Foundation
import UniformTypeIdentifiers

public actor BookImportPipeline {
    public static let maximumSourceBytes = 100 * 1_024 * 1_024
    private let storage: FileStorage
    private let extractors: [any BookTextExtractor]
    private let nameFinder: NameCandidateFinder

    public init(
        storage: FileStorage,
        extractors: [any BookTextExtractor] = [TXTExtractor(), PDFTextExtractor(), EPUBExtractor()],
        nameFinder: NameCandidateFinder = NameCandidateFinder()
    ) {
        self.storage = storage
        self.extractors = extractors
        self.nameFinder = nameFinder
    }

    public func importBook(
        from sourceURL: URL,
        title overrideTitle: String? = nil,
        author overrideAuthor: String? = nil,
        progress: @Sendable (ImportStage) -> Void
    ) async throws -> ImportedBook {
        let bookID = UUID()
        do {
            progress(.validating)
            try Task.checkCancellation()
            let type = try contentType(for: sourceURL)
            let resourceValues = try sourceURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            )
            guard resourceValues.isSymbolicLink != true else {
                throw BookLensError.invalidOutputPath
            }
            let sourceBytes: Int
            if resourceValues.isRegularFile == true {
                sourceBytes = resourceValues.fileSize ?? 0
            } else if resourceValues.isDirectory == true,
                      sourceURL.pathExtension.lowercased() == "epub" {
                sourceBytes = try boundedDirectorySize(at: sourceURL)
            } else {
                throw BookLensError.unsupportedBook
            }
            guard sourceBytes > 0, sourceBytes <= Self.maximumSourceBytes else {
                throw BookLensError.bookTooLarge(limitMegabytes: Self.maximumSourceBytes / 1_024 / 1_024)
            }
            guard let extractor = extractors.first(where: { $0.supports(type) }) else {
                throw BookLensError.unsupportedBook
            }

            progress(.copying)
            let storedSource = try await storage.copyOriginal(from: sourceURL, bookID: bookID)
            try Task.checkCancellation()

            progress(.extracting)
            let extracted = try await extractor.extract(from: storedSource)
            try Task.checkCancellation()
            let extractedCover = try? await BookCoverExtractor().extractCover(from: storedSource)
            let storedCover: URL?
            if let extractedCover {
                storedCover = try? await storage.storeBookCover(
                    data: extractedCover.data,
                    fileExtension: extractedCover.fileExtension,
                    bookID: bookID
                )
            } else {
                storedCover = nil
            }

            progress(.splittingChapters)
            let title = nonEmpty(overrideTitle)
                ?? nonEmpty(extracted.title)
                ?? sourceURL.deletingPathExtension().lastPathComponent
            let author = nonEmpty(overrideAuthor) ?? nonEmpty(extracted.author) ?? "Author not specified"

            progress(.normalizing)
            var globalOffset = 0
            let chapters: [Chapter] = extracted.chapters.enumerated().map { index, extractedChapter in
                let length = extractedChapter.text.count
                defer { globalOffset += length + 2 }
                return Chapter(
                    bookID: bookID,
                    index: index,
                    title: extractedChapter.title,
                    text: extractedChapter.text,
                    normalizedRange: globalOffset..<(globalOffset + length)
                )
            }

            progress(.indexing)
            try Task.checkCancellation()

            progress(.findingNames)
            let candidates = nameFinder.find(in: extracted.chapters)
            try Task.checkCancellation()

            let book = Book(
                id: bookID,
                title: title,
                author: author,
                language: extracted.language,
                sourceFilename: sourceURL.lastPathComponent
            )
            progress(.finished)
            return ImportedBook(
                book: book,
                storedSourceURL: storedSource,
                coverURL: storedCover,
                coverSource: storedCover == nil ? "none" : extractedCover?.source ?? "none",
                chapters: chapters,
                nameCandidates: candidates
            )
        } catch {
            try? await storage.removeImportedBook(bookID: bookID)
            if error is CancellationError {
                throw BookLensError.cancelled
            }
            throw error
        }
    }

    private func contentType(for url: URL) throws -> UTType {
        if url.pathExtension.lowercased() == "epub" {
            return UTType(importedAs: "org.idpf.epub-container")
        }
        if let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type
        }
        throw BookLensError.unsupportedBook
    }

    private func boundedDirectorySize(at root: URL) throws -> Int {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            throw BookLensError.unsupportedBook
        }
        var byteCount = 0
        var entryCount = 0
        while let item = enumerator.nextObject() as? URL {
            entryCount += 1
            guard entryCount <= 20_000 else { throw BookLensError.unsupportedBook }
            let values = try item.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw BookLensError.invalidOutputPath }
            if values.isRegularFile == true {
                byteCount += values.fileSize ?? 0
                guard byteCount <= Self.maximumSourceBytes else {
                    throw BookLensError.bookTooLarge(limitMegabytes: Self.maximumSourceBytes / 1_024 / 1_024)
                }
            }
        }
        return byteCount
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
