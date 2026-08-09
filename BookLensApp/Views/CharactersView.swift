import BookLensData
import SwiftData
import SwiftUI

struct CharactersView: View {
    @Bindable var model: AppModel
    @Query(sort: \CharacterRecord.name) private var characters: [CharacterRecord]
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 16)]

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if filteredCharacters.isEmpty {
                    ContentUnavailableView {
                        Label("Main characters haven’t been found yet", systemImage: "person.3.sequence.fill")
                    } description: {
                        Text("Add a book or search by title — AI will build the list automatically.")
                    } actions: {
                        Button("Home") { model.selectedSection = .library }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(filteredCharacters) { character in
                                CharacterVisualCard(
                                    character: character,
                                    artwork: latestArtwork(for: character.id),
                                    isSelected: model.selectedCharacterID == character.id
                                ) {
                                    model.selectedBookID = character.book?.id
                                    model.selectedCharacterID = character.id
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

            if let selectedCharacter {
                Divider()
                CharacterInspectorView(
                    model: model,
                    character: selectedCharacter,
                    artwork: latestArtwork(for: selectedCharacter.id)
                ) {
                    model.selectedCharacterID = nil
                }
                .frame(width: 390)
            }
        }
        .navigationTitle(BookLensLocalization.string("Main characters"))
        .searchable(text: $searchText, prompt: "Name, book, or role")
    }

    private var filteredCharacters: [CharacterRecord] {
        let available = characters.filter { $0.isMainCharacter && !$0.isExcluded }
        guard !searchText.isEmpty else { return available }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.role.localizedCaseInsensitiveContains(searchText)
                || ($0.book?.title.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selectedCharacter: CharacterRecord? {
        guard let id = model.selectedCharacterID else { return nil }
        return filteredCharacters.first { $0.id == id }
            ?? characters.first { $0.id == id && $0.isMainCharacter }
    }

    private func latestArtwork(for characterID: UUID) -> ArtworkRecord? {
        artworks.first { $0.characterID == characterID }
    }
}
