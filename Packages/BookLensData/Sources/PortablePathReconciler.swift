import Foundation
import SwiftData

public struct PortablePathRepairSummary: Equatable, Sendable {
    public let bookSources: Int
    public let bookCovers: Int
    public let jobDirectories: Int
    public let artworks: Int

    public var total: Int {
        bookSources + bookCovers + jobDirectories + artworks
    }
}

public struct PortablePathResolver: Sendable {
    public let storageRoot: URL

    public init(storageRoot: URL) {
        self.storageRoot = storageRoot.standardizedFileURL
    }

    public func bookSourcePath(
        bookID: UUID,
        sourceFilename: String,
        currentPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard !exists(currentPath, fileManager: fileManager) else { return nil }

        let sourceDirectory = storageRoot
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("Source", isDirectory: true)
        let preferredNames = [
            URL(fileURLWithPath: currentPath).lastPathComponent,
            URL(fileURLWithPath: sourceFilename).lastPathComponent,
        ]

        if let match = firstExistingFile(
            in: sourceDirectory,
            preferredNames: preferredNames,
            fileManager: fileManager
        ) {
            return match.path
        }
        return nil
    }

    public func artworkPath(
        artworkID: UUID,
        filename: String,
        currentPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard !exists(currentPath, fileManager: fileManager) else { return nil }

        let artworkDirectory = storageRoot.appendingPathComponent("Artworks", isDirectory: true)
        let preferredNames = [
            URL(fileURLWithPath: currentPath).lastPathComponent,
            URL(fileURLWithPath: filename).lastPathComponent,
        ]
        if let match = firstExistingFile(
            in: artworkDirectory,
            preferredNames: preferredNames,
            fileManager: fileManager
        ) {
            return match.path
        }

        let idPrefix = artworkID.uuidString.lowercased() + "."
        guard let contents = try? fileManager.contentsOfDirectory(
            at: artworkDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents.first { url in
            url.lastPathComponent.lowercased().hasPrefix(idPrefix)
                && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
        }?.standardizedFileURL.path
    }

    public func bookCoverPath(
        bookID: UUID,
        currentPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard !exists(currentPath, fileManager: fileManager) else { return nil }
        let coverDirectory = storageRoot
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("Cover", isDirectory: true)
        return firstExistingFile(
            in: coverDirectory,
            preferredNames: [URL(fileURLWithPath: currentPath).lastPathComponent],
            fileManager: fileManager
        )?.path
    }

    public func jobOutputDirectoryPath(
        jobID: UUID,
        currentPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard !exists(currentPath, fileManager: fileManager) else { return nil }

        let candidate = storageRoot
            .appendingPathComponent("Jobs", isDirectory: true)
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("output", isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return candidate.path
    }

    private func exists(_ path: String, fileManager: FileManager) -> Bool {
        !path.isEmpty && fileManager.fileExists(atPath: path)
    }

    private func firstExistingFile(
        in directory: URL,
        preferredNames: [String],
        fileManager: FileManager
    ) -> URL? {
        for name in preferredNames where !name.isEmpty {
            let candidate = directory.appendingPathComponent(name, isDirectory: false).standardizedFileURL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let files = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        }
        return files.count == 1 ? files[0].standardizedFileURL : nil
    }
}

@MainActor
public enum PortablePathReconciler {
    @discardableResult
    public static func reconcile(
        in modelContext: ModelContext,
        storageRoot: URL,
        fileManager: FileManager = .default
    ) throws -> PortablePathRepairSummary {
        let resolver = PortablePathResolver(storageRoot: storageRoot)
        var repairedBookSources = 0
        var repairedBookCovers = 0
        var repairedJobDirectories = 0
        var repairedArtworks = 0

        for book in try modelContext.fetch(FetchDescriptor<BookRecord>()) {
            if let path = resolver.bookSourcePath(
                bookID: book.id,
                sourceFilename: book.sourceFilename,
                currentPath: book.storedSourcePath,
                fileManager: fileManager
            ) {
                book.storedSourcePath = path
                repairedBookSources += 1
            }
            if let path = resolver.bookCoverPath(
                bookID: book.id,
                currentPath: book.coverPath,
                fileManager: fileManager
            ) {
                book.coverPath = path
                repairedBookCovers += 1
            }
        }

        for job in try modelContext.fetch(FetchDescriptor<GenerationJobRecord>()) {
            if let path = resolver.jobOutputDirectoryPath(
                jobID: job.id,
                currentPath: job.outputDirectoryPath,
                fileManager: fileManager
            ) {
                job.outputDirectoryPath = path
                repairedJobDirectories += 1
            }
        }

        for artwork in try modelContext.fetch(FetchDescriptor<ArtworkRecord>()) {
            if let path = resolver.artworkPath(
                artworkID: artwork.id,
                filename: artwork.filename,
                currentPath: artwork.storedPath,
                fileManager: fileManager
            ) {
                artwork.storedPath = path
                repairedArtworks += 1
            }
        }

        let summary = PortablePathRepairSummary(
            bookSources: repairedBookSources,
            bookCovers: repairedBookCovers,
            jobDirectories: repairedJobDirectories,
            artworks: repairedArtworks
        )
        if summary.total > 0 {
            try modelContext.save()
        }
        return summary
    }
}
