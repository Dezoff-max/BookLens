import BookLensSupport
import Foundation
import UniformTypeIdentifiers

public struct TXTExtractor: BookTextExtractor {
    private let maximumSourceBytes: Int
    private let maximumTextCharacters: Int

    public init(
        maximumSourceBytes: Int = BookImportPipeline.maximumSourceBytes,
        maximumTextCharacters: Int = 2_000_000
    ) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumTextCharacters = maximumTextCharacters
    }

    public func supports(_ type: UTType) -> Bool {
        type.conforms(to: .plainText)
    }

    public func extract(from url: URL) async throws -> ExtractedBook {
        try Task.checkCancellation()
        let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteCount > 0, byteCount <= maximumSourceBytes else {
            throw BookLensError.bookTooLarge(limitMegabytes: maximumSourceBytes / 1_024 / 1_024)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1251]
        guard let text = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
            throw BookLensError.unsupportedBook
        }
        let normalized = TextNormalizer().normalize(text)
        guard normalized.count <= maximumTextCharacters else {
            throw BookLensError.extractedTextTooLarge(limitCharacters: maximumTextCharacters)
        }
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookLensError.unsupportedBook
        }
        return ExtractedBook(
            title: url.deletingPathExtension().lastPathComponent,
            chapters: ChapterSegmenter().segment(normalized)
        )
    }
}
