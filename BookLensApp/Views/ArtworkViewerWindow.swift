import AppKit
import BookLensData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ArtworkViewerWindow: View {
    let artworkID: UUID
    @Query private var artworks: [ArtworkRecord]
    @Query private var books: [BookRecord]
    @State private var zoom = 1.0
    @State private var exportError: String?

    var body: some View {
        Group {
            if let artwork, let image = NSImage(contentsOfFile: artwork.storedPath) {
                VStack(spacing: 0) {
                    viewerToolbar(artwork)
                    Divider().overlay(.white.opacity(0.15))
                    GeometryReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(proxy.size.width * zoom, proxy.size.width),
                                    height: max(proxy.size.height * zoom, proxy.size.height)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    NSApp.keyWindow?.toggleFullScreen(nil)
                                }
                        }
                        .background(Color.black)
                    }
                }
                .background(Color.black)
            } else {
                ContentUnavailableView(
                    "Image unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("The local file was moved or deleted.")
                )
            }
        }
        .navigationTitle(characterName)
        .frame(minWidth: 720, minHeight: 520)
        .alert(
            "Could not save photo",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func viewerToolbar(_ artwork: ArtworkRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(characterName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(bookName) · \(artwork.pixelWidth) × \(artwork.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Button {
                zoom = max(0.5, zoom - 0.25)
            } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .disabled(zoom <= 0.5)

            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 48)

            Button {
                zoom = min(4, zoom + 0.25)
            } label: {
                Label("Zoom in", systemImage: "plus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .disabled(zoom >= 4)

            Button {
                zoom = 1
            } label: {
                Label("Fit to window", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
            }

            Divider().frame(height: 22)

            Button {
                copy(artwork)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }

            Button {
                export(artwork)
            } label: {
                Label("Save photo…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
            }
            .help("Full screen · double-click the image")
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.94))
    }

    private var artwork: ArtworkRecord? {
        artworks.first { $0.id == artworkID }
    }

    private var characterName: String {
        guard let artwork else { return BookLensLocalization.string("Image") }
        return books.flatMap(\.characters).first { $0.id == artwork.characterID }?.name
            ?? BookLensLocalization.string("Character")
    }

    private var bookName: String {
        guard let artwork else { return BookLensLocalization.string("Book") }
        return books.first { $0.id == artwork.bookID }?.title
            ?? BookLensLocalization.string("Book")
    }

    private func copy(_ artwork: ArtworkRecord) {
        guard let image = NSImage(contentsOfFile: artwork.storedPath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func export(_ artwork: ArtworkRecord) {
        let source = URL(fileURLWithPath: artwork.storedPath)
        let panel = NSSavePanel()
        panel.title = BookLensLocalization.string("Save photo")
        panel.nameFieldStringValue = artwork.filename
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: source.pathExtension) {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != source.standardizedFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
