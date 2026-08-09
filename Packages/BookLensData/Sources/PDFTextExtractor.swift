@preconcurrency import PDFKit
import BookLensSupport
import Foundation
import UniformTypeIdentifiers

public struct PDFTextExtractor: BookTextExtractor {
    private let minimumTextCharacters: Int
    private let maximumPageCount: Int
    private let maximumTextCharacters: Int

    public init(
        minimumTextCharacters: Int = 80,
        maximumPageCount: Int = 2_500,
        maximumTextCharacters: Int = 2_000_000
    ) {
        self.minimumTextCharacters = minimumTextCharacters
        self.maximumPageCount = maximumPageCount
        self.maximumTextCharacters = maximumTextCharacters
    }

    public func supports(_ type: UTType) -> Bool {
        type.conforms(to: .pdf)
    }

    public func extract(from url: URL) async throws -> ExtractedBook {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url) else {
            throw BookLensError.unsupportedBook
        }
        guard document.pageCount <= maximumPageCount else {
            throw BookLensError.pdfPageLimitExceeded(maximumPages: maximumPageCount)
        }
        var pages: [String] = []
        var extractedCharacterCount = 0
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            if let text = document.page(at: index)?.string {
                pages.append(text)
                extractedCharacterCount += text.count
                if extractedCharacterCount > maximumTextCharacters {
                    throw BookLensError.extractedTextTooLarge(limitCharacters: maximumTextCharacters)
                }
            }
        }
        let normalized = TextNormalizer().normalize(pages.joined(separator: "\n\n"))
        let meaningfulCount = normalized.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        guard meaningfulCount >= minimumTextCharacters else {
            throw BookLensError.pdfWithoutTextLayer
        }
        return ExtractedBook(
            title: document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                ?? url.deletingPathExtension().lastPathComponent,
            author: document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
            chapters: ChapterSegmenter().segment(normalized)
        )
    }
}
