import AppKit
import BookLensData
import SwiftUI

struct AppleBooksImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isDropTargeted = false
    @State private var message: String?
    @State private var assets: [AppleBooksAsset] = []
    @State private var isScanning = false
    @State private var didScan = false

    let onChooseFile: () -> Void
    let onImport: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            instructions
            discoverySection
            dropZone

            Label {
                Text("Purchases protected by Apple FairPlay DRM cannot be imported. They appear with a lock; BookLens does not bypass protection.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Apple Books") { openAppleBooks() }
                    .buttonStyle(.borderedProminent)
                Button("Open PDF folder") { openPersonalBooksFolder() }
                Button("Choose EPUB or PDF…") {
                    dismiss()
                    onChooseFile()
                }
                Spacer()
            }
        }
        .padding(26)
        .frame(width: 760, height: 680)
        .task { await scanLibrary() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36))
                .foregroundStyle(BookLensTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Apple Books")
                    .font(.title2.bold())
                Text("BookLens finds downloaded PDF and EPUB files automatically — you do not need to know the path.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
        }
    }

    private var instructions: some View {
        HStack(alignment: .top, spacing: 18) {
            instruction(number: 1, title: "Download", detail: "Wait for the download to finish in Apple Books.")
            instruction(number: 2, title: "Find", detail: "BookLens will check the local Books folders.")
            instruction(number: 3, title: "Import", detail: "Choose an available PDF or EPUB below.")
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloaded books")
                        .font(.headline)
                    Text(discoveryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await scanLibrary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }

            Group {
                if isScanning && !didScan {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking the local Apple Books library…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 118)
                } else if assets.isEmpty {
                    ContentUnavailableView(
                        "No files found yet",
                        systemImage: "books.vertical",
                        description: Text("Download a book or choose your own EPUB/PDF manually.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 118)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(assets) { asset in
                                assetRow(asset)
                                if asset.id != assets.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(height: 154)
                }
            }
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2))
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(isDropTargeted ? BookLensTheme.accent : .secondary)
            Text(isDropTargeted ? "Drop the file" : "Or drop an EPUB/PDF here")
                .font(.headline)
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text("A books.apple.com link is not a book file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDropTargeted ? BookLensTheme.accent.opacity(0.08) : Color.primary.opacity(0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDropTargeted ? BookLensTheme.accent : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            accept(urls.first)
        } isTargeted: { isDropTargeted = $0 }
    }

    private var discoveryStatus: String {
        if isScanning { return "Refreshing list…" }
        guard didScan else { return "Search has not run yet" }
        let available = assets.filter(\.isImportable).count
        let protected = assets.count - available
        if protected == 0 { return "Available to import: \(available)" }
        return "Available: \(available) · DRM protected: \(protected)"
    }

    private func assetRow(_ asset: AppleBooksAsset) -> some View {
        HStack(spacing: 11) {
            Image(systemName: asset.kind == .pdf ? "doc.richtext" : "book.closed")
                .font(.title3)
                .foregroundStyle(asset.isImportable ? BookLensTheme.accent : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.title)
                    .lineLimit(1)
                    .font(.callout.weight(.medium))
                Text(assetDetail(asset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if asset.isImportable {
                Button("Import") { importAsset(asset) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Label("FairPlay DRM", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .help("Apple protects this purchase; no accessible EPUB or PDF is available.")
            }
        }
        .padding(.vertical, 8)
    }

    private func assetDetail(_ asset: AppleBooksAsset) -> String {
        var parts = [asset.kind.rawValue.uppercased()]
        parts.append(asset.source == .iCloudBooks ? "iCloud Books" : "Apple Books download")
        if let fileSize = asset.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func instruction(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(String(number))
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(BookLensTheme.accent.opacity(0.16), in: Circle())
                .foregroundStyle(BookLensTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func scanLibrary() async {
        guard !isScanning else { return }
        isScanning = true
        let result = await Task.detached(priority: .utility) {
            AppleBooksLibraryLocator().scan()
        }.value
        assets = result
        didScan = true
        isScanning = false
    }

    private func accept(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard url.isFileURL else {
            if url.host?.localizedCaseInsensitiveContains("books.apple.com") == true {
                message = "This is a store link, not an EPUB/PDF. Download the book; FairPlay DRM purchases cannot be imported."
            } else {
                message = "Choose a local EPUB or PDF file, not an internet link."
            }
            return false
        }
        guard let asset = AppleBooksLibraryLocator().asset(at: url) else {
            message = "Choose a local EPUB or PDF file."
            return false
        }
        guard asset.isImportable else {
            message = "This book is protected by Apple FairPlay DRM and cannot be imported."
            return false
        }
        importAsset(asset)
        return true
    }

    private func importAsset(_ asset: AppleBooksAsset) {
        message = nil
        dismiss()
        onImport(asset.url)
    }

    private func openAppleBooks() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iBooksX") else {
            message = "Apple Books was not found on this Mac."
            return
        }
        guard NSWorkspace.shared.open(appURL) else {
            message = "Could not open Apple Books."
            return
        }
        message = nil
    }

    private func openPersonalBooksFolder() {
        let locator = AppleBooksLibraryLocator()
        guard let folder = locator.folders.first(where: {
            $0.source == .iCloudBooks && FileManager.default.fileExists(atPath: $0.url.path)
        }) else {
            message = "The iCloud Books folder does not exist yet. Download or add a personal file in Apple Books first."
            return
        }
        guard NSWorkspace.shared.open(folder.url) else {
            message = "Could not open the Apple Books folder in Finder."
            return
        }
        message = nil
    }
}
