import Foundation

public enum BookLensError: Error, Equatable, Sendable {
    case codexNotFound
    case incompatibleCodexVersion(found: String, supported: String)
    case handshakeFailed
    case authenticationRequired
    case rateLimitExceeded
    case protocolViolation(code: String)
    case invalidStructuredOutput
    case unsupportedBook
    case pdfWithoutTextLayer
    case drmProtectedBook
    case bookTooLarge(limitMegabytes: Int)
    case extractedTextTooLarge(limitCharacters: Int)
    case pdfPageLimitExceeded(maximumPages: Int)
    case cancelled
    case timeout(operation: String)
    case outputFileMissing
    case multipleOutputFiles
    case invalidImage
    case invalidOutputPath
    case storageUnavailable

    public var diagnosticCode: String {
        switch self {
        case .codexNotFound: "BLX-CODEX-001"
        case .incompatibleCodexVersion: "BLX-CODEX-002"
        case .handshakeFailed: "BLX-CODEX-003"
        case .authenticationRequired: "BLX-AUTH-001"
        case .rateLimitExceeded: "BLX-LIMIT-001"
        case .protocolViolation: "BLX-RPC-001"
        case .invalidStructuredOutput: "BLX-SCHEMA-001"
        case .unsupportedBook: "BLX-IMPORT-001"
        case .pdfWithoutTextLayer: "BLX-IMPORT-002"
        case .drmProtectedBook: "BLX-IMPORT-003"
        case .bookTooLarge: "BLX-IMPORT-004"
        case .extractedTextTooLarge: "BLX-IMPORT-005"
        case .pdfPageLimitExceeded: "BLX-IMPORT-006"
        case .cancelled: "BLX-CANCEL-001"
        case .timeout: "BLX-TIMEOUT-001"
        case .outputFileMissing: "BLX-IMAGE-001"
        case .multipleOutputFiles: "BLX-IMAGE-002"
        case .invalidImage: "BLX-IMAGE-003"
        case .invalidOutputPath: "BLX-STORAGE-001"
        case .storageUnavailable: "BLX-STORAGE-002"
        }
    }
}

extension BookLensError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "Codex was not found. Install a compatible version and check again."
        case let .incompatibleCodexVersion(found, supported):
            "Codex version \(found) is incompatible. Supported: \(supported)."
        case .handshakeFailed:
            "Codex started, but the handshake did not complete."
        case .authenticationRequired:
            "ChatGPT sign-in is required."
        case .rateLimitExceeded:
            "The Codex limit has been reached. Try again after it resets."
        case .protocolViolation:
            "Codex returned a response that does not match the pinned protocol."
        case .invalidStructuredOutput:
            "The character profile failed local validation."
        case .unsupportedBook:
            "Unsupported book format. Choose EPUB, TXT, or a text-based PDF."
        case .pdfWithoutTextLayer:
            "The PDF does not contain enough extractable text. OCR is not included in the MVP."
        case .drmProtectedBook:
            "The book is protected by Apple FairPlay DRM. BookLens cannot import or bypass this protection."
        case let .bookTooLarge(limitMegabytes):
            "The book exceeds the \(limitMegabytes) MB size limit."
        case let .extractedTextTooLarge(limitCharacters):
            "The extracted text exceeds the safe limit of \(limitCharacters) characters."
        case let .pdfPageLimitExceeded(maximumPages):
            "The PDF exceeds the safe limit of \(maximumPages) pages."
        case .cancelled:
            "The operation was cancelled."
        case let .timeout(operation):
            "The “\(operation)” operation timed out."
        case .outputFileMissing:
            "Codex completed the turn, but no validated image file was found."
        case .multipleOutputFiles:
            "Multiple new images were found in the job folder."
        case .invalidImage:
            "The result file is not a valid decodable image."
        case .invalidOutputPath:
            "The result path is outside the current job folder."
        case .storageUnavailable:
            "BookLens local storage is unavailable."
        }
    }
}
