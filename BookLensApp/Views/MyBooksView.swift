import AppKit
import BookLensData
import SwiftData
import SwiftUI

struct MyBooksView: View {
    @Bindable var model: AppModel
    @Query(sort: \BookRecord.importedAt, order: .reverse) private var allBooks: [BookRecord]
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @State private var searchText = ""
    @State private var sortOrder = BookSortOrder.recent
    @State private var audienceFilter = BookAudienceFilter.all
    @State private var bookToEdit: BookRecord?

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 22)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if importedBooks.isEmpty {
                ContentUnavailableView {
                    Label("There are no books in your library yet", systemImage: "books.vertical")
                } description: {
                    Text("Add an EPUB, PDF, or TXT file. Online-only book descriptions are not shown here.")
                } actions: {
                    Button("Add book…") {
                        model.isFileImporterPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if displayedBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(displayedBooks) { book in
                            ImportedBookCard(
                                book: book,
                                coverArtwork: preferredCoverArtwork(for: book, from: artworks)
                            ) {
                                openReader(book)
                            } openCharacters: {
                                model.selectedBookID = book.id
                                model.selectedCharacterID = book.characters.first(where: { $0.isMainCharacter })?.id
                                model.selectedSection = .library
                            } reveal: {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: book.storedSourcePath),
                                ])
                            } editClassification: {
                                bookToEdit = book
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(BookLensLocalization.string("My books"))
        .searchable(text: $searchText, prompt: "Title or author")
        .sheet(item: $bookToEdit) { book in
            BookClassificationEditor(book: book)
                .environment(\.locale, model.preferredLocale)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("My books")
                        .font(.largeTitle.bold())
                    Text("Only EPUB, PDF, and TXT files added to this Mac")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add book…", systemImage: "plus") {
                    model.isFileImporterPresented = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 16) {
                Picker("Audience", selection: $audienceFilter) {
                    ForEach(BookAudienceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 560)

                Spacer()
                Picker("Sort", selection: $sortOrder) {
                    ForEach(BookSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .frame(width: 210)
            }
        }
        .padding(28)
    }

    private var importedBooks: [BookRecord] {
        allBooks.filter { $0.sourceKind == "local" && !$0.storedSourcePath.isEmpty }
    }

    private var displayedBooks: [BookRecord] {
        let filtered = importedBooks.filter { book in
            let matchesSearch = searchText.isEmpty
                || book.title.localizedCaseInsensitiveContains(searchText)
                || book.author.localizedCaseInsensitiveContains(searchText)
                || book.genres.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesSearch && audienceFilter.matches(book)
        }
        switch sortOrder {
        case .recent:
            return filtered.sorted { $0.importedAt > $1.importedAt }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            return filtered.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        }
    }

    private func openReader(_ book: BookRecord) {
        model.selectedBookID = book.id
        model.selectedCharacterID = nil
    }
}

private enum BookAudienceFilter: String, CaseIterable, Identifiable {
    case all
    case children
    case teen
    case adult

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .children: "Children"
        case .teen: "Teen"
        case .adult: "Adult"
        }
    }

    func matches(_ book: BookRecord) -> Bool {
        switch self {
        case .all: true
        case .children: book.audience == BookAudience.children.rawValue
        case .teen: book.audience == BookAudience.teen.rawValue
        case .adult: book.audience == BookAudience.adult.rawValue
        }
    }
}

private enum BookSortOrder: String, CaseIterable, Identifiable {
    case recent
    case title
    case author

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .recent: "Newest first"
        case .title: "By title"
        case .author: "By author"
        }
    }
}

private struct ImportedBookCard: View {
    let book: BookRecord
    let coverArtwork: ArtworkRecord?
    let read: () -> Void
    let openCharacters: () -> Void
    let reveal: () -> Void
    let editClassification: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: read) {
                BookCoverView(book: book, artwork: coverArtwork)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.68, contentMode: .fit)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(book.sourceFilename.pathExtension.uppercased(), systemImage: "doc")
                    Text("·")
                    Text(verbatim: "\(book.chapterCount) \(BookLensLocalization.string("sections"))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                BookClassificationBadges(book: book)
            }

            if let progress = ReaderProgressStore.progress(for: book) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    Text(verbatim: "\(BookLensLocalization.string("Read progress")) \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Read", systemImage: "book.pages", action: read)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Menu {
                    Button("Open characters", action: openCharacters)
                    Button("Edit classification…", systemImage: "tag", action: editClassification)
                    Divider()
                    Button("Show file in Finder", action: reveal)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Book actions")
            }
        }
        .padding(14)
        .bookLensCard()
        .contextMenu {
            Button("Read", action: read)
            Button("Open characters", action: openCharacters)
            Button("Edit classification…", action: editClassification)
            Divider()
            Button("Show file in Finder", action: reveal)
        }
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
}
