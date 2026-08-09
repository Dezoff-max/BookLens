import BookLensSupport
import Foundation

public actor FileStorage {
    public let rootURL: URL

    public init(rootURL: URL? = nil) throws {
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BookLensError.storageUnavailable
            }
            self.rootURL = applicationSupport.appendingPathComponent("BookLens", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    public func copyOriginal(from sourceURL: URL, bookID: UUID) throws -> URL {
        let bookDirectory = try directory(named: "Library/\(bookID.uuidString.lowercased())")
        let sourceDirectory = bookDirectory.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let safeName = sanitizedFilename(sourceURL.lastPathComponent)
        let destination = sourceDirectory.appendingPathComponent(safeName, isDirectory: false)
        let temporary = sourceDirectory.appendingPathComponent(".\(UUID().uuidString).partial")
        try FileManager.default.copyItem(at: sourceURL, to: temporary)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = false
            var visibleDestination = destination
            try? visibleDestination.setResourceValues(resourceValues)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }

    public func createJobWorkspace(jobID: UUID) throws -> URL {
        let job = try directory(named: "Jobs/\(jobID.uuidString.lowercased())")
        try FileManager.default.createDirectory(
            at: job.appendingPathComponent("input", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: job.appendingPathComponent("output", isDirectory: true),
            withIntermediateDirectories: true
        )
        return job
    }

    public func storeBookCover(data: Data, fileExtension: String, bookID: UUID) throws -> URL {
        let allowed = Set(["jpg", "jpeg", "png", "webp"])
        let normalizedExtension = fileExtension.lowercased()
        guard allowed.contains(normalizedExtension), !data.isEmpty else {
            throw BookLensError.invalidOutputPath
        }
        let coverDirectory = try directory(named: "Library/\(bookID.uuidString.lowercased())/Cover")
        let destination = coverDirectory.appendingPathComponent("cover.\(normalizedExtension)")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let temporary = coverDirectory.appendingPathComponent(".\(UUID().uuidString).partial")
        try data.write(to: temporary, options: .atomic)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }

    public func moveValidatedArtwork(from sourceURL: URL, artworkID: UUID) throws -> URL {
        let directory = try directory(named: "Artworks")
        let fileExtension = sourceURL.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(
            "\(artworkID.uuidString.lowercased()).\(fileExtension)",
            isDirectory: false
        )
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).partial")
        try FileManager.default.copyItem(at: sourceURL, to: temporary)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = false
            var visibleDestination = destination
            try? visibleDestination.setResourceValues(resourceValues)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }

    public func removeTemporaryJob(jobID: UUID) throws {
        let jobsRoot = rootURL.appendingPathComponent("Jobs", isDirectory: true)
        let target = jobsRoot.appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        let resolvedRoot = jobsRoot.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let resolvedTarget = target.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard resolvedTarget.hasPrefix(resolvedRoot), FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    public func removeImportedBook(bookID: UUID) throws {
        let libraryRoot = rootURL.appendingPathComponent("Library", isDirectory: true)
        let target = libraryRoot.appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
        let resolvedRoot = libraryRoot.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let resolvedTarget = target.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard resolvedTarget.hasPrefix(resolvedRoot), FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    private func directory(named relativePath: String) throws -> URL {
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: true)
        let root = rootURL.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(root) else {
            throw BookLensError.invalidOutputPath
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sanitizedFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\0").union(.newlines)
        let parts = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        return parts.joined(separator: "_").prefix(180).description
    }
}
