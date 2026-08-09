import AppKit
import BookLensData
import SwiftUI

struct CharacterArtworkView: View {
    let character: CharacterRecord
    let artwork: ArtworkRecord?
    var cornerRadius: CGFloat = 14
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.055)

                if let artwork, let image = NSImage(contentsOfFile: artwork.storedPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [BookLensTheme.blueAccent.opacity(0.9), BookLensTheme.accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.rectangle.fill")
                            .font(.system(size: 48, weight: .light))
                        Text(initials)
                            .font(.title2.bold())
                    }
                    .foregroundStyle(.white.opacity(0.94))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.09))
        }
        .accessibilityLabel(BookLensLocalization.string(artwork == nil ? "Image not created yet" : "Generated character image"))
    }

    private var initials: String {
        character.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct CharacterVisualCard: View {
    let character: CharacterRecord
    let artwork: ArtworkRecord?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                CharacterArtworkView(character: character, artwork: artwork, cornerRadius: 12)
                    .frame(height: 210)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: character.role.isEmpty ? character.book?.title ?? BookLensLocalization.string("Character") : character.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? BookLensTheme.accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(character.name), \(character.role)")
        .accessibilityHint(BookLensLocalization.string("Open character card"))
    }
}

struct CharacterInspectorView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let character: CharacterRecord
    let artwork: ArtworkRecord?
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(character.name).font(.title2.bold())
                        Text(character.book.map { "\($0.title) · \($0.author)" } ?? character.role)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                CharacterArtworkView(
                    character: character,
                    artwork: artwork,
                    contentMode: .fit
                )
                .aspectRatio(artworkAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)

                if let artwork {
                    Button {
                        openWindow(value: artwork.id)
                    } label: {
                        Label("Open image", systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    creationButton("Portrait", icon: "person.crop.rectangle", mode: .portrait)
                    creationButton("Full body", icon: "figure.stand", mode: .fullBody)
                    creationButton("In a scene", icon: "theatermasks", mode: .scene)
                    creationButton("Book world", icon: "person.3.sequence.fill", mode: .bookWorld)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description from the book")
                        .font(.headline)
                    Text(verbatim: character.summary.isEmpty ? BookLensLocalization.string("AI hasn’t prepared this character’s description yet.") : character.summary)
                        .foregroundStyle(character.summary.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                if !character.traits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance and traits")
                            .font(.headline)
                        ForEach(character.traits.prefix(6)) { trait in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: trait.evidenceIDs.isEmpty ? "sparkles" : "checkmark.seal.fill")
                                    .foregroundStyle(trait.evidenceIDs.isEmpty ? .secondary : BookLensTheme.accent)
                                Text("\(trait.category): \(trait.value)")
                            }
                        }
                    }
                }

                DisclosureGroup("Review sources") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(evidence.prefix(6)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: item.chapter?.title ?? BookLensLocalization.string("Source"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BookLensTheme.accent)
                                Text(item.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                            if item.id != evidence.prefix(6).last?.id { Divider() }
                        }
                        if evidence.isEmpty {
                            Text("No supporting excerpts found yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 310, idealWidth: 360, maxWidth: 420)
        .background(.ultraThinMaterial)
    }

    private var artworkAspectRatio: CGFloat {
        guard let artwork,
              artwork.pixelWidth > 0,
              artwork.pixelHeight > 0
        else { return 0.82 }
        let ratio = CGFloat(artwork.pixelWidth) / CGFloat(artwork.pixelHeight)
        return min(max(ratio, 0.72), 1.8)
    }

    private var evidence: [EvidenceRecord] {
        guard let book = character.book else { return [] }
        let ids = Set(character.traits.flatMap(\.evidenceIDs))
        let all = book.chapters.sorted { $0.index < $1.index }.flatMap(\.evidence)
        if !ids.isEmpty { return all.filter { ids.contains($0.id) } }
        return all.filter { $0.characterName.localizedCaseInsensitiveCompare(character.name) == .orderedSame }
    }

    private func creationButton(_ title: LocalizedStringKey, icon: String, mode: CharacterCreationMode) -> some View {
        Button {
            model.selectedBookID = character.book?.id
            model.selectedCharacterID = character.id
            model.selectedCreationMode = mode
            model.selectedSection = .studio
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(BookLensTheme.accent)
        .controlSize(.large)
        .disabled(character.traits.isEmpty)
        .help(BookLensLocalization.string(character.traits.isEmpty ? "Finish AI book analysis first" : "Create image"))
    }
}
