import Foundation

enum CodexProcessEnvironment {
    static func augmented(
        base: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var environment = base
        let preferredDirectories = [
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true).path,
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true).path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
        ]
        let inheritedDirectories = (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }

        var seen = Set<String>()
        environment["PATH"] = (preferredDirectories + inheritedDirectories)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }
}
