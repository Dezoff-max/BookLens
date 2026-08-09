import Foundation
import BookLensSupport
import OSLog

enum BookLensDiagnosticLevel: String, Sendable {
    case info = "INFO"
    case error = "ERROR"
}

actor BookLensDiagnostics {
    static let shared = BookLensDiagnostics()

    nonisolated static let logURL: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("BookLens", isDirectory: true)
            .appendingPathComponent("BookLens.log", isDirectory: false)
    }()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dmitry.booklens",
        category: "AI"
    )
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL
    private let forceEnabled: Bool?
    private let redactor = Redactor()

    init(logURL: URL = BookLensDiagnostics.logURL, forceEnabled: Bool? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
        fileURL = logURL
        self.forceEnabled = forceEnabled
    }

    func record(
        _ event: String,
        level: BookLensDiagnosticLevel = .info,
        fields: [String: String] = [:]
    ) {
        guard diagnosticsAreEnabled else { return }

        let renderedFields = fields
            .sorted { $0.key < $1.key }
            .map { "\(sanitize($0.key))=\(sanitize($0.value))" }
            .joined(separator: " ")
        let message = [
            formatter.string(from: .now),
            level.rawValue,
            sanitize(event),
            renderedFields,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        switch level {
        case .info:
            logger.info("\(message, privacy: .private)")
        case .error:
            logger.error("\(message, privacy: .private)")
        }

        append(message + "\n")
    }

    private var diagnosticsAreEnabled: Bool {
        if let forceEnabled { return forceEnabled }
        return UserDefaults.standard.bool(forKey: "diagnosticsEnabled")
    }

    private func append(_ line: String) {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try rotateIfNeeded(fileManager: fileManager)
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            logger.error("diagnostics.file-write-failed")
        }
    }

    private func rotateIfNeeded(fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        guard let size = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
              size.intValue >= 5_000_000
        else { return }

        let previous = fileURL.deletingLastPathComponent()
            .appendingPathComponent("BookLens.previous.log", isDirectory: false)
        if fileManager.fileExists(atPath: previous.path) {
            try fileManager.removeItem(at: previous)
        }
        try fileManager.moveItem(at: fileURL, to: previous)
    }

    private func sanitize(_ value: String) -> String {
        let singleLine = redactor.redact(value)
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\t", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return String(singleLine.prefix(180))
    }
}
