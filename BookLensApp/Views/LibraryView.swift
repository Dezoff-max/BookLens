import BookLensData
import BookLensSupport
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookRecord.importedAt, order: .reverse) private var books: [BookRecord]
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @State private var searchText = ""
    @State private var pendingImportURL: URL?
    @State private var bookPendingDeletion: BookRecord?
    @State private var bookToEdit: BookRecord?
    @State private var expandedBookIDs: Set<UUID> = []

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    welcomeHeader
                    searchBar
                    primaryActions
                    booksSection
                    charactersSection
                    discoveryCallout
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)

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
        .navigationTitle(BookLensLocalization.string("Home"))
        .onReceive(NotificationCenter.default.publisher(for: .bookLensBeginImport)) { notification in
            pendingImportURL = notification.object as? URL
        }
        .sheet(isPresented: Binding(
            get: { pendingImportURL != nil },
            set: { if !$0 { pendingImportURL = nil } }
        )) {
            if let pendingImportURL, let pipeline = model.importPipeline {
                ImportWizardView(sourceURL: pendingImportURL, pipeline: pipeline) { imported in
                    persist(imported)
                    self.pendingImportURL = nil
                    model.selectedBookID = imported.book.id
                    model.selectedSection = .library
                }
                .environment(\.locale, model.preferredLocale)
            }
        }
        .sheet(isPresented: $model.isAppleBooksImportPresented) {
            AppleBooksImportView {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    model.isFileImporterPresented = true
                }
            } onImport: { url in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    pendingImportURL = url
                }
            }
            .environment(\.locale, model.preferredLocale)
        }
        .sheet(isPresented: $model.isBookDiscoveryPresented) {
            WebBookSearchView(model: model, initialQuery: model.discoveryQuery)
                .environment(\.locale, model.preferredLocale)
        }
        .sheet(item: $bookToEdit) { book in
            BookClassificationEditor(book: book)
                .environment(\.locale, model.preferredLocale)
        }
        .alert(
            "Remove this book from the library?",
            isPresented: Binding(
                get: { bookPendingDeletion != nil },
                set: { if !$0 { bookPendingDeletion = nil } }
            ),
            presenting: bookPendingDeletion
        ) { book in
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        if book.sourceKind == "local", let storage = model.storage {
                            try await storage.removeImportedBook(bookID: book.id)
                        }
                        modelContext.delete(book)
                        try modelContext.save()
                        bookPendingDeletion = nil
                    } catch {
                        model.lastError = .storageUnavailable
                    }
                }
            }
            Button("Cancel", role: .cancel) { bookPendingDeletion = nil }
        } message: { book in
            Text("“\(book.title)”, its characters, and related images will be removed. The original file outside BookLens will not change.")
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visualize characters from books")
                .font(.system(size: 32, weight: .bold))
            Text("Add your own book or search by title — AI will identify its main characters.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
            TextField("Book title, author, or character…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 10)
                .onSubmit { openDiscovery() }
            Button("Search") { openDiscovery() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .frame(maxWidth: 760)
    }

    private var primaryActions: some View {
        HStack(spacing: 14) {
            actionCard(
                title: "Add your own book",
                subtitle: "EPUB, PDF, or TXT — AI will find the main characters",
                icon: "square.and.arrow.down",
                button: "Choose file"
            ) {
                model.isFileImporterPresented = true
            }
            actionCard(
                title: "No book file?",
                subtitle: "Enter a title — AI will find the synopsis and characters online",
                icon: "globe.europe.africa.fill",
                button: "Find a book"
            ) {
                model.discoveryQuery = searchText
                model.isBookDiscoveryPresented = true
            }
        }
    }

    private func actionCard(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String,
        button: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(BookLensTheme.accent)
                .frame(width: 50, height: 50)
                .background(BookLensTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: action) { Text(button) }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .bookLensCard()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var booksSection: some View {
        if !localBooks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("My books").font(.title2.bold())
                    Spacer()
                    Button("From Apple Books", systemImage: "books.vertical") {
                        model.isAppleBooksImportPresented = true
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(localBooks) { book in
                            CompactBookCard(
                                book: book,
                                coverArtwork: preferredCoverArtwork(for: book, from: artworks)
                            ) {
                                model.selectedBookID = book.id
                                model.selectedCharacterID = book.characters.first(where: { $0.isMainCharacter })?.id
                            } delete: {
                                bookPendingDeletion = book
                            }
                        }
                    }
                }
            }
        }
    }

    private var charactersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Characters by book").font(.title2.bold())
                    Text(verbatim: BookLensLocalization.string(mainCharacters.isEmpty ? "The actual main characters will appear here after analysis" : "Choose a character and create their image"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !mainCharacters.isEmpty {
                    Button("View all") { model.selectedSection = .characters }
                }
            }

            if mainCharacters.isEmpty {
                ContentUnavailableView {
                    Label("No characters found yet", systemImage: "person.3.sequence.fill")
                } description: {
                    Text("Add a book or search by title — no manual tagging required.")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .bookLensCard()
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(booksWithMainCharacters) { book in
                        characterShelf(for: book, characters: mainCharacters(in: book))
                    }
                }
                .onAppear { initializeExpandedShelves() }
            }
        }
    }

    private func characterShelf(for book: BookRecord, characters: [CharacterRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BookCoverView(
                    book: book,
                    artwork: preferredCoverArtwork(for: book, from: artworks),
                    cornerRadius: 8
                )
                    .frame(width: 42, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: "\(book.author) · \(characters.count) \(BookLensLocalization.string("characters"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BookClassificationBadges(book: book, maximumGenres: 1)
                }

                Spacer()

                Button("Category", systemImage: "tag") {
                    bookToEdit = book
                }
                .buttonStyle(.bordered)

                Button("Open book") {
                    model.selectedBookID = book.id
                    model.selectedCharacterID = characters.first?.id
                }
                .buttonStyle(.bordered)

                Button {
                    toggleShelf(book.id)
                } label: {
                    Label(
                        expandedBookIDs.contains(book.id) ? "Collapse" : "Expand",
                        systemImage: expandedBookIDs.contains(book.id) ? "chevron.up" : "chevron.down"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help(expandedBookIDs.contains(book.id) ? "Collapse characters" : "Show characters")
            }

            if expandedBookIDs.contains(book.id) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(characters) { character in
                            CharacterVisualCard(
                                character: character,
                                artwork: latestArtwork(for: character.id),
                                isSelected: model.selectedCharacterID == character.id
                            ) {
                                model.selectedBookID = book.id
                                model.selectedCharacterID = character.id
                            }
                            .frame(width: 205)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(verbatim: "\(characters.count) \(BookLensLocalization.string("characters")) · \(BookLensLocalization.string("Use the arrow to show character cards"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .bookLensCard()
    }

    private var discoveryCallout: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(BookLensTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn’t find the book or character?").font(.headline)
                Text("Enter a title, author, or name — AI will check public book sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Search online") {
                model.discoveryQuery = searchText
                model.isBookDiscoveryPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .bookLensCard()
    }

    private var mainCharacters: [CharacterRecord] {
        books
            .flatMap(\.characters)
            .filter { $0.isMainCharacter && !$0.isExcluded }
            .sorted { lhs, rhs in
                if lhs.occurrenceCount == rhs.occurrenceCount { return lhs.name < rhs.name }
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
    }

    private var booksWithMainCharacters: [BookRecord] {
        books.filter { !mainCharacters(in: $0).isEmpty }
    }

    private func mainCharacters(in book: BookRecord) -> [CharacterRecord] {
        book.characters
            .filter { $0.isMainCharacter && !$0.isExcluded }
            .sorted { lhs, rhs in
                if lhs.occurrenceCount == rhs.occurrenceCount { return lhs.name < rhs.name }
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
    }

    private var localBooks: [BookRecord] {
        books.filter { $0.sourceKind == "local" }
    }

    private var selectedCharacter: CharacterRecord? {
        guard let id = model.selectedCharacterID else { return nil }
        return mainCharacters.first { $0.id == id }
    }

    private func latestArtwork(for characterID: UUID) -> ArtworkRecord? {
        artworks.first { $0.characterID == characterID }
    }

    private func initializeExpandedShelves() {
        guard expandedBookIDs.isEmpty, let first = booksWithMainCharacters.first else { return }
        expandedBookIDs.insert(first.id)
    }

    private func toggleShelf(_ bookID: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedBookIDs.contains(bookID) {
                expandedBookIDs.remove(bookID)
            } else {
                expandedBookIDs.insert(bookID)
            }
        }
    }

    private func openDiscovery() {
        model.discoveryQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        model.isBookDiscoveryPresented = true
    }

    private func persist(_ imported: ImportedBook) {
        let chapterRecords = imported.chapters.map { chapter in
            ChapterRecord(
                id: chapter.id,
                index: chapter.index,
                title: chapter.title,
                text: chapter.text,
                rangeStart: chapter.normalizedRange.lowerBound,
                rangeEnd: chapter.normalizedRange.upperBound
            )
        }
        let characterRecords = imported.nameCandidates.map { candidate in
            CharacterRecord(
                name: candidate.name,
                occurrenceCount: candidate.occurrenceCount,
                origin: "candidate"
            )
        }

        for candidate in imported.nameCandidates {
            for evidence in candidate.evidence where evidence.chapterIndex < chapterRecords.count {
                chapterRecords[evidence.chapterIndex].evidence.append(
                    EvidenceRecord(
                        id: evidence.id,
                        characterName: candidate.name,
                        text: evidence.excerpt,
                        rangeStart: evidence.localRange.lowerBound,
                        rangeEnd: evidence.localRange.upperBound,
                        digest: SHA256Digest.string(for: evidence.excerpt)
                    )
                )
            }
        }

        let record = BookRecord(
            id: imported.book.id,
            title: imported.book.title,
            author: imported.book.author,
            language: imported.book.language,
            sourceFilename: imported.book.sourceFilename,
            storedSourcePath: imported.storedSourceURL.path,
            analysisStatus: "pending",
            sourceKind: "local",
            coverPath: imported.coverURL?.path ?? "",
            coverSource: imported.coverSource,
            chapters: chapterRecords,
            characters: characterRecords
        )
        modelContext.insert(record)
        try? modelContext.save()
    }
}

private struct CompactBookCard: View {
    let book: BookRecord
    let coverArtwork: ArtworkRecord?
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                BookCoverView(book: book, artwork: coverArtwork, cornerRadius: 8)
                    .frame(width: 52, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label {
                        Text(verbatim: BookLensLocalization.string(book.analysisStatus == "ready" ? "Characters found" : "AI analysis needed"))
                    } icon: {
                        Image(systemName: book.analysisStatus == "ready" ? "checkmark.circle.fill" : "sparkles")
                    }
                        .font(.caption2)
                        .foregroundStyle(book.analysisStatus == "ready" ? .green : BookLensTheme.accent)
                }
            }
            .padding(10)
            .frame(width: 250, alignment: .leading)
            .bookLensCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", action: open)
            Divider()
            Button("Remove from library…", role: .destructive, action: delete)
        }
    }
}
