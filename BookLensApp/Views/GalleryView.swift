import AppKit
import BookLensData
import SwiftData
import SwiftUI

struct GalleryView: View {
    @Bindable var model: AppModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @Query private var books: [BookRecord]
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var comparison: [ArtworkRecord] = []
    @State private var artworkPendingDeletion: ArtworkRecord?

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gallery").font(.largeTitle.bold())
                    Text("All generated images are stored locally on this Mac")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Favorites", isOn: $favoritesOnly)
                    .toggleStyle(.button)
                if comparison.count == 2 {
                    Button("Compare") { }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            Divider()

            if filteredArtworks.isEmpty {
                ContentUnavailableView(
                    "The gallery is empty",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Create the first image from a character profile.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(filteredArtworks) { artwork in
                            ArtworkCard(
                                artwork: artwork,
                                characterName: characterName(for: artwork),
                                isCompared: comparison.contains(where: { $0.id == artwork.id }),
                                isBookCover: books.first(where: { $0.id == artwork.bookID })?.coverArtworkID == artwork.id,
                                onOpen: { openWindow(value: artwork.id) },
                                onCompare: { toggleComparison(artwork) },
                                onFavorite: {
                                    artwork.isFavorite.toggle()
                                    try? modelContext.save()
                                },
                                onPrimary: { makePrimary(artwork) },
                                onBookCover: { toggleBookCover(artwork) },
                                onReference: {
                                    model.selectedBookID = artwork.bookID
                                    model.selectedCharacterID = artwork.characterID
                                    model.selectedSection = .studio
                                },
                                onExport: { export(artwork) },
                                onCopy: { copy(artwork) },
                                onReveal: { reveal(artwork) },
                                onDelete: { artworkPendingDeletion = artwork }
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(BookLensLocalization.string("Gallery"))
        .searchable(text: $searchText, prompt: "Book, character, or style")
        .sheet(isPresented: Binding(
            get: { comparison.count == 2 },
            set: { if !$0 { comparison = [] } }
        )) {
            ComparisonSheet(artworks: comparison)
                .environment(\.locale, model.preferredLocale)
        }
        .alert(
            "Delete image?",
            isPresented: Binding(
                get: { artworkPendingDeletion != nil },
                set: { if !$0 { artworkPendingDeletion = nil } }
            ),
            presenting: artworkPendingDeletion
        ) { artwork in
            Button("Remove", role: .destructive) {
                if let book = books.first(where: { $0.coverArtworkID == artwork.id }) {
                    book.coverArtworkID = nil
                }
                try? FileManager.default.removeItem(atPath: artwork.storedPath)
                modelContext.delete(artwork)
                try? modelContext.save()
                artworkPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { artworkPendingDeletion = nil }
        } message: { artwork in
            Text("The file \(artwork.filename) and its local record will be permanently deleted.")
        }
    }

    private var filteredArtworks: [ArtworkRecord] {
        artworks.filter { artwork in
            (!favoritesOnly || artwork.isFavorite)
                && (searchText.isEmpty
                    || artwork.style.localizedCaseInsensitiveContains(searchText)
                    || characterName(for: artwork).localizedCaseInsensitiveContains(searchText)
                    || bookName(for: artwork).localizedCaseInsensitiveContains(searchText))
        }
    }

    private func characterName(for artwork: ArtworkRecord) -> String {
        books.flatMap(\.characters).first { $0.id == artwork.characterID }?.name ?? "Character"
    }

    private func bookName(for artwork: ArtworkRecord) -> String {
        books.first { $0.id == artwork.bookID }?.title ?? "Book"
    }

    private func toggleComparison(_ artwork: ArtworkRecord) {
        if let index = comparison.firstIndex(where: { $0.id == artwork.id }) {
            comparison.remove(at: index)
        } else if comparison.count < 2 {
            comparison.append(artwork)
        } else {
            comparison = [comparison[1], artwork]
        }
    }

    private func makePrimary(_ artwork: ArtworkRecord) {
        for item in artworks where item.characterID == artwork.characterID {
            item.isPrimary = item.id == artwork.id
        }
        try? modelContext.save()
    }

    private func toggleBookCover(_ artwork: ArtworkRecord) {
        guard let book = books.first(where: { $0.id == artwork.bookID }) else { return }
        book.coverArtworkID = book.coverArtworkID == artwork.id ? nil : artwork.id
        try? modelContext.save()
    }

    private func copy(_ artwork: ArtworkRecord) {
        guard let image = NSImage(contentsOfFile: artwork.storedPath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func reveal(_ artwork: ArtworkRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artwork.storedPath)])
    }

    private func export(_ artwork: ArtworkRecord) {
        let source = URL(fileURLWithPath: artwork.storedPath)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artwork.filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSSound.beep()
        }
    }
}

private struct ArtworkCard: View {
    @Bindable var artwork: ArtworkRecord
    let characterName: String
    let isCompared: Bool
    let isBookCover: Bool
    let onOpen: () -> Void
    let onCompare: () -> Void
    let onFavorite: () -> Void
    let onPrimary: () -> Void
    let onBookCover: () -> Void
    let onReference: () -> Void
    let onExport: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let image = NSImage(contentsOfFile: artwork.storedPath) {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    ContentUnavailableView("File unavailable", systemImage: "photo.badge.exclamationmark")
                }
                HStack {
                    if artwork.isPrimary {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    if isBookCover {
                        Label("Cover", systemImage: "book.closed.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                    }
                    Button(action: onFavorite) {
                        Image(systemName: artwork.isFavorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .background(Color.black.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .bottomTrailing) {
                Button("Open", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .padding(9)
            }
            .onTapGesture(count: 2, perform: onOpen)

            Text(characterName).font(.headline)
            Text(styleTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(artwork.pixelWidth) × \(artwork.pixelHeight)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            HStack {
                Button("Open", systemImage: "photo", action: onOpen)
                Button(isCompared ? "Selected" : "Compare", action: onCompare)
                Spacer()
                Menu {
                    Button("Set as primary", action: onPrimary)
                    Button(
                        isBookCover ? "Restore original cover" : "Use as book cover",
                        systemImage: isBookCover ? "arrow.uturn.backward" : "book.closed.fill",
                        action: onBookCover
                    )
                    Button("Use as reference", action: onReference)
                    Divider()
                    Button("Export…", action: onExport)
                    Button("Copy", action: onCopy)
                    Button("Show in Finder", action: onReveal)
                    Divider()
                    Button("Delete…", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(12)
        .bookLensCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var styleTitle: String {
        let key: String
        switch artwork.style {
        case "cinematicRealism": key = "Cinematic realism"
        case "classicBookIllustration": key = "Classic book illustration"
        case "engraving": key = "Engraving"
        case "watercolor": key = "Watercolor"
        case "graphicNovel": key = "Graphic novel"
        case "atmosphericPainting": key = "Atmospheric painting"
        case "neutralStudioPortrait": key = "Studio portrait"
        default: return artwork.style
        }
        return BookLensLocalization.string(key)
    }
}

private struct ComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artworks: [ArtworkRecord]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Version comparison").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }
            HSplitView {
                ForEach(artworks) { artwork in
                    if let image = NSImage(contentsOfFile: artwork.storedPath) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 1_100, height: 760)
    }
}
