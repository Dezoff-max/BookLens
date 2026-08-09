@testable import BookLensCodex
import Foundation
import XCTest

final class CodexExecutableResolverTests: XCTestCase {
    func testFinderEnvironmentResolvesNativeNPMCodex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCodexResolverTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent(nativeExecutableRelativePath)
        try makeExecutable(at: executable, body: "echo 'codex-cli 0.146.9'")

        let installation = try await CodexExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            bundleExecutableDirectory: nil,
            homeDirectory: root,
            trustedPrefixes: [root],
            trustedTeamIdentifiers: []
        ).resolve()

        XCTAssertEqual(installation.executableURL.standardizedFileURL, executable.standardizedFileURL)
        XCTAssertEqual(installation.version, "0.146.9")
        XCTAssertEqual(installation.compatibility, .compatible)
    }

    func testBrokenOverrideFallsThroughToNativeCandidate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCodexResolverTest-\(UUID().uuidString)", isDirectory: true)
        let fallbackRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCodexResolverTest-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: fallbackRoot)
        }

        let broken = root.appendingPathComponent(nativeExecutableRelativePath)
        try makeExecutable(at: broken, body: "exit 1")
        let native = fallbackRoot.appendingPathComponent(nativeExecutableRelativePath)
        try makeExecutable(at: native, body: "echo 'codex-cli 0.146.0'")

        let installation = try await CodexExecutableResolver(
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            bundleExecutableDirectory: nil,
            homeDirectory: root,
            trustedPrefixes: [root, fallbackRoot],
            trustedTeamIdentifiers: []
        ).resolve()

        XCTAssertEqual(installation.executableURL.standardizedFileURL, native.standardizedFileURL)
    }

    func testRejectsGroupWritableExecutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCodexResolverTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent(nativeExecutableRelativePath)
        try makeExecutable(at: executable, body: "echo 'codex-cli 0.146.0'")
        try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: executable.path)

        await XCTAssertThrowsErrorAsync {
            _ = try await CodexExecutableResolver(
                environment: [:],
                bundleExecutableDirectory: nil,
                homeDirectory: root,
                trustedPrefixes: [root],
                trustedTeamIdentifiers: []
            ).resolve()
        }
    }

    func testRejectsUnsignedExecutableInTrustedPrefix() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCodexResolverTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent(nativeExecutableRelativePath)
        try makeExecutable(at: executable, body: "echo 'codex-cli 0.146.0'")

        await XCTAssertThrowsErrorAsync {
            _ = try await CodexExecutableResolver(
                environment: [:],
                bundleExecutableDirectory: nil,
                homeDirectory: root,
                trustedPrefixes: [root]
            ).resolve()
        }
    }

    func testAcceptsNewerCodexVersion() {
        XCTAssertTrue(CodexExecutableResolver.versionIsSupported("0.200.1"))
        XCTAssertFalse(CodexExecutableResolver.versionIsSupported("0.145.9"))
    }

    func testGUIProcessPathIncludesUserAndHomebrewBinsWithoutDuplicates() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let environment = CodexProcessEnvironment.augmented(
            base: ["PATH": "/usr/bin:/bin:/opt/homebrew/bin"],
            homeDirectory: home
        )
        let components = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        XCTAssertEqual(components.first, "/Users/fixture/.npm-global/bin")
        XCTAssertTrue(components.contains("/opt/homebrew/bin"))
        XCTAssertEqual(components.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    private var nativeExecutableRelativePath: String {
#if arch(arm64)
        "lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
#else
        "lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex"
#endif
    }

    private func makeExecutable(at url: URL, body: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch { }
}
