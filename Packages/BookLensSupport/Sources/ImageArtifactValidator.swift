import CryptoKit
import Foundation
import ImageIO

public struct ValidatedImage: Equatable, Sendable {
    public let url: URL
    public let sha256: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int

    public init(url: URL, sha256: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int) {
        self.url = url
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }
}

public struct ImageArtifactValidator: Sendable {
    private static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]

    public init() {}

    public func snapshot(directory: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        return Set(urls.map(\.lastPathComponent))
    }

    public func discoverAndValidate(
        in outputDirectory: URL,
        excluding snapshot: Set<String>
    ) throws -> ValidatedImage {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ).filter { url in
            !snapshot.contains(url.lastPathComponent)
                && Self.allowedExtensions.contains(url.pathExtension.lowercased())
        }

        guard !candidates.isEmpty else {
            throw BookLensError.outputFileMissing
        }
        guard candidates.count == 1 else {
            throw BookLensError.multipleOutputFiles
        }
        return try validate(candidates[0], inside: outputDirectory)
    }

    public func waitForNewImage(
        in outputDirectory: URL,
        excluding snapshot: Set<String>,
        timeout: Duration = .seconds(30)
    ) async throws -> ValidatedImage {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            do {
                return try discoverAndValidate(in: outputDirectory, excluding: snapshot)
            } catch BookLensError.outputFileMissing {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw BookLensError.outputFileMissing
    }

    public func validate(_ imageURL: URL, inside outputDirectory: URL) throws -> ValidatedImage {
        let root = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = imageURL.standardizedFileURL
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])

        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BookLensError.invalidOutputPath
        }

        let resolved = candidate.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPath) else {
            throw BookLensError.invalidOutputPath
        }

        guard let source = CGImageSourceCreateWithURL(resolved as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            throw BookLensError.invalidImage
        }

        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ValidatedImage(
            url: resolved,
            sha256: digest,
            pixelWidth: width,
            pixelHeight: height,
            byteCount: data.count
        )
    }
}
