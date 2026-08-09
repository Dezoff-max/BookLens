import Foundation

public enum AppleBooksAssetKind: String, Hashable, Sendable {
    case epub
    case pdf
}

public enum AppleBooksAssetAvailability: Hashable, Sendable {
    case importable
    case drmProtected
}

public enum AppleBooksAssetSource: Hashable, Sendable {
    case iCloudBooks
    case downloadedStoreBook
}

public struct AppleBooksAsset: Identifiable, Hashable, Sendable {
    public let url: URL
    public let title: String
    public let kind: AppleBooksAssetKind
    public let availability: AppleBooksAssetAvailability
    public let source: AppleBooksAssetSource
    public let fileSize: Int?

    public var id: String { url.standardizedFileURL.path }

    public var isImportable: Bool {
        availability == .importable
    }
}

public struct AppleBooksLibraryLocator: Sendable {
    public struct LibraryFolder: Hashable, Sendable {
        public let url: URL
        public let source: AppleBooksAssetSource

        public init(url: URL, source: AppleBooksAssetSource) {
            self.url = url
            self.source = source
        }
    }

    public let folders: [LibraryFolder]

    public init(folders: [LibraryFolder]? = nil) {
        if let folders {
            self.folders = folders
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        self.folders = [
            LibraryFolder(
                url: home.appendingPathComponent(
                    "Library/Mobile Documents/iCloud~com~apple~iBooks/Documents",
                    isDirectory: true
                ),
                source: .iCloudBooks
            ),
            LibraryFolder(
                url: home.appendingPathComponent(
                    "Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books",
                    isDirectory: true
                ),
                source: .downloadedStoreBook
            ),
        ]
    }

    public func scan() -> [AppleBooksAsset] {
        var found: [String: AppleBooksAsset] = [:]
        for folder in folders where FileManager.default.fileExists(atPath: folder.url.path) {
            for asset in scan(folder) {
                found[asset.id] = asset
            }
        }
        return found.values.sorted { lhs, rhs in
            if lhs.isImportable != rhs.isImportable { return lhs.isImportable }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public func asset(at url: URL, source: AppleBooksAssetSource = .iCloudBooks) -> AppleBooksAsset? {
        classify(url, source: source)
    }

    private func scan(_ folder: LibraryFolder) -> [AppleBooksAsset] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: folder.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var assets: [AppleBooksAsset] = []
        var inspectedCount = 0
        while let candidate = enumerator.nextObject() as? URL, inspectedCount < 20_000 {
            inspectedCount += 1
            guard let values = try? candidate.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true
            else {
                continue
            }

            let fileExtension = candidate.pathExtension.lowercased()
            if fileExtension == "epub", values.isDirectory == true {
                enumerator.skipDescendants()
            }
            guard fileExtension == "pdf" || fileExtension == "epub",
                  let asset = classify(candidate, source: folder.source)
            else {
                continue
            }
            assets.append(asset)
        }
        return assets
    }

    private func classify(_ url: URL, source: AppleBooksAssetSource) -> AppleBooksAsset? {
        let fileExtension = url.pathExtension.lowercased()
        guard let kind = AppleBooksAssetKind(rawValue: fileExtension),
              let values = try? url.resourceValues(forKeys: [
                  .isDirectoryKey,
                  .isRegularFileKey,
                  .isSymbolicLinkKey,
                  .fileSizeKey,
              ]),
              values.isSymbolicLink != true,
              values.isDirectory == true || values.isRegularFile == true
        else {
            return nil
        }

        let drmProtected = kind == .epub
            && values.isDirectory == true
            && isAppleDRMProtected(packageURL: url)
        let title = kind == .epub && values.isDirectory == true
            ? epubTitle(packageURL: url)
            : nil

        return AppleBooksAsset(
            url: url,
            title: nonEmpty(title) ?? url.deletingPathExtension().lastPathComponent,
            kind: kind,
            availability: drmProtected ? .drmProtected : .importable,
            source: source,
            fileSize: values.isRegularFile == true ? values.fileSize : nil
        )
    }

    private func isAppleDRMProtected(packageURL: URL) -> Bool {
        let metadata = packageURL.appendingPathComponent("META-INF", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.appendingPathComponent("sinf.xml").path) {
            return true
        }
        let encryptionURL = metadata.appendingPathComponent("encryption.xml")
        guard let size = try? encryptionURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2 * 1_024 * 1_024,
              let data = try? Data(contentsOf: encryptionURL, options: [.mappedIfSafe])
        else {
            return false
        }
        return String(decoding: data, as: UTF8.self)
            .localizedCaseInsensitiveContains("http://itunes.apple.com/dataenc")
    }

    private func epubTitle(packageURL: URL) -> String? {
        let containerURL = packageURL.appendingPathComponent("META-INF/container.xml")
        guard let containerParser = XMLParser(contentsOf: containerURL) else { return nil }
        let containerDelegate = AppleBooksContainerDelegate()
        containerParser.delegate = containerDelegate
        guard containerParser.parse(), let opfPath = containerDelegate.opfPath,
              isSafeRelativePath(opfPath)
        else {
            return nil
        }

        let opfURL = packageURL.appendingPathComponent(opfPath).standardizedFileURL
        let rootPath = packageURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard opfURL.resolvingSymlinksInPath().path.hasPrefix(rootPath),
              let parser = XMLParser(contentsOf: opfURL)
        else {
            return nil
        }
        let delegate = AppleBooksTitleDelegate()
        parser.delegate = delegate
        return parser.parse() ? delegate.title : nil
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && !components.contains("..") && !components.contains("")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private final class AppleBooksContainerDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName.hasSuffix("rootfile"), let path = attributeDict["full-path"] {
            opfPath = path
        }
    }
}

private final class AppleBooksTitleDelegate: NSObject, XMLParserDelegate {
    var title: String?
    private var isInsideTitle = false
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "title", title == nil {
            isInsideTitle = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTitle { buffer.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "title", isInsideTitle else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { title = value }
        isInsideTitle = false
    }
}
