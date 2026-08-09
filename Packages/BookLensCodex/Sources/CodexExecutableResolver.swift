import BookLensSupport
import Foundation

public struct CodexInstallation: Equatable, Sendable {
    public enum Compatibility: Equatable, Sendable {
        case compatible
        case incompatible(supported: String)
    }

    public let executableURL: URL
    public let version: String
    public let architecture: String
    public let compatibility: Compatibility
    public let signingTeamIdentifier: String

    public init(
        executableURL: URL,
        version: String,
        architecture: String,
        compatibility: Compatibility,
        signingTeamIdentifier: String
    ) {
        self.executableURL = executableURL
        self.version = version
        self.architecture = architecture
        self.compatibility = compatibility
        self.signingTeamIdentifier = signingTeamIdentifier
    }
}

public struct CodexExecutableResolver: Sendable {
    public static let minimumVersion = "0.146.0"
    public static let supportedVersionDescription = "0.146.0 or later"

    private let environment: [String: String]
    private let bundleExecutableDirectory: URL?
    private let trustedPrefixes: [URL]
    private let trustedTeamIdentifiers: Set<String>

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleExecutableDirectory: URL? = Bundle.main.executableURL?.deletingLastPathComponent(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        trustedPrefixes: [URL]? = nil,
        trustedTeamIdentifiers: Set<String> = ["2DC432GLL2"]
    ) {
        self.environment = CodexProcessEnvironment.augmented(
            base: environment,
            homeDirectory: homeDirectory
        )
        self.bundleExecutableDirectory = bundleExecutableDirectory
        self.trustedPrefixes = trustedPrefixes ?? [
            URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
            URL(fileURLWithPath: "/usr/local", isDirectory: true),
        ]
        self.trustedTeamIdentifiers = trustedTeamIdentifiers
    }

    public func resolve() async throws -> CodexInstallation {
        for candidate in candidateURLs() where isTrustedExecutable(candidate) {
            do {
                guard let signingTeamIdentifier = signingTeamIdentifier(for: candidate) else {
                    continue
                }
                let version = try await readVersion(at: candidate)
                let compatibility: CodexInstallation.Compatibility = Self.versionIsSupported(version)
                    ? .compatible
                    : .incompatible(supported: Self.supportedVersionDescription)
                return CodexInstallation(
                    executableURL: candidate.resolvingSymlinksInPath(),
                    version: version,
                    architecture: architectureName,
                    compatibility: compatibility,
                    signingTeamIdentifier: signingTeamIdentifier
                )
            } catch {
                // Finder launches GUI apps with a minimal PATH. A discovered npm
                // wrapper can therefore be executable but still fail to start;
                // continue to the next independent candidate, especially native Codex.
                continue
            }
        }
        throw BookLensError.codexNotFound
    }

    private func candidateURLs() -> [URL] {
        var urls: [URL] = []
        for prefix in trustedPrefixes {
            urls.append(prefix.appendingPathComponent(nativeNPMExecutableRelativePath))
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func signingTeamIdentifier(for url: URL) -> String? {
        if trustedTeamIdentifiers.isEmpty {
            return "TEST-FIXTURE"
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", url.resolvingSymlinksInPath().path]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            guard let line = lines.first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
                return nil
            }
            let team = String(line.dropFirst("TeamIdentifier=".count))
            return trustedTeamIdentifiers.contains(team) ? team : nil
        } catch {
            return nil
        }
    }

    private var nativeNPMExecutableRelativePath: String {
#if arch(arm64)
        "lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
#elseif arch(x86_64)
        "lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex"
#else
        "lib/node_modules/@openai/codex/native-unavailable"
#endif
    }

    private func isTrustedExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let trustedRoots = trustedPrefixes + (bundleExecutableDirectory.map { [$0] } ?? [])
        guard trustedRoots.contains(where: { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/")
        }),
        FileManager.default.isExecutableFile(atPath: resolved.path),
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
        let fileType = attributes[.type] as? FileAttributeType,
        fileType == .typeRegular,
        let permissions = attributes[.posixPermissions] as? NSNumber,
        permissions.intValue & 0o022 == 0
        else {
            return false
        }
        return true
    }

    static func versionIsSupported(_ version: String) -> Bool {
        func components(_ value: String) -> [Int]? {
            let parts = value.split(separator: ".")
            guard parts.count >= 3 else { return nil }
            let numbers = parts.prefix(3).compactMap { part in
                Int(part.prefix { $0.isNumber })
            }
            return numbers.count == 3 ? numbers : nil
        }
        guard let found = components(version), let minimum = components(Self.minimumVersion) else {
            return false
        }
        return found.lexicographicallyPrecedes(minimum) == false
    }

    private func readVersion(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = url
                process.arguments = ["--version"]
                process.environment = environment
                process.standardOutput = output
                process.standardError = output
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let text = String(decoding: data, as: UTF8.self)
                    guard process.terminationStatus == 0,
                          let version = text.split(whereSeparator: \.isWhitespace).last
                    else {
                        throw BookLensError.codexNotFound
                    }
                    continuation.resume(returning: String(version))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private var architectureName: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
