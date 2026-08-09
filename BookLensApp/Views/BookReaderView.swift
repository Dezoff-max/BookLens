import AppKit
import BookLensData
import SwiftData
import SwiftUI

struct BookReaderView: View {
    @Bindable var model: AppModel
    let book: BookRecord
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]

    @State private var selectedChapterID: UUID?
    @State private var searchText = ""
    @State private var showsSettings = false
    @State private var showsContents = true
    @AppStorage("reader.fontSize") private var fontSize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 8.0
    @AppStorage("reader.pageWidth") private var pageWidth = 720.0
    @AppStorage("reader.fontDesign") private var fontDesign = ReaderFontDesign.serif.rawValue
    @AppStorage("reader.theme") private var readerTheme = ReaderTheme.system.rawValue

    init(model: AppModel, book: BookRecord) {
        self.model = model
        self.book = book
        let sorted = book.chapters.sorted { $0.index < $1.index }
        _selectedChapterID = State(
            initialValue: ReaderProgressStore.chapterID(for: book.id) ?? sorted.first?.id
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()
            HStack(spacing: 0) {
                if showsContents {
                    contentsSidebar
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)
                    Divider()
                }
                readingSurface
            }
        }
        .navigationTitle(book.title)
        .onAppear {
            if currentChapter == nil {
                selectedChapterID = chapters.first?.id
            }
            saveProgress()
        }
        .onChange(of: selectedChapterID) { _, _ in saveProgress() }
    }

    private var readerToolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.selectedBookID = nil
            } label: {
                Label("My books", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Button {
                showsContents.toggle()
            } label: {
                Label("Contents", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
            }
            .help("Show or hide contents")

            Divider().frame(height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !chapters.isEmpty {
                Text(verbatim: "\(currentChapterNumber) \(BookLensLocalization.string("of")) \(chapters.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                showsSettings.toggle()
            } label: {
                Label("Reading settings", systemImage: "textformat.size")
                    .labelStyle(.iconOnly)
            }
            .popover(isPresented: $showsSettings, arrowEdge: .bottom) {
                ReaderSettingsView(
                    fontSize: $fontSize,
                    lineSpacing: $lineSpacing,
                    pageWidth: $pageWidth,
                    fontDesign: $fontDesign,
                    readerTheme: $readerTheme
                )
            }
            .help("Font, size, and background")

            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
            }
            .help("Open the reader full screen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var contentsSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BookCoverView(
                        book: book,
                        artwork: preferredCoverArtwork(for: book, from: artworks),
                        cornerRadius: 8
                    )
                        .frame(width: 58, height: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(3)
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this book", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)

            Divider()

            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selectedChapterID) {
                    ForEach(searchResults) { chapter in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chapter.title)
                                .lineLimit(2)
                            if !searchText.isEmpty {
                                Text(searchSnippet(for: chapter))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(chapter.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var readingSurface: some View {
        if let chapter = currentChapter {
            ZStack {
                theme.background
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(chapter.title)
                            .font(.system(size: fontSize + 10, weight: .bold, design: design.design))
                            .foregroundStyle(theme.foreground)
                            .padding(.bottom, 28)

                        ForEach(Array(paragraphs(in: chapter).enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.system(size: fontSize, design: design.design))
                                .foregroundStyle(theme.foreground)
                                .lineSpacing(lineSpacing)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 16)
                        }

                        chapterNavigation
                            .padding(.top, 26)
                    }
                    .frame(maxWidth: pageWidth, alignment: .leading)
                    .padding(.horizontal, 54)
                    .padding(.vertical, 52)
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            ContentUnavailableView(
                "No readable text is available",
                systemImage: "text.book.closed",
                description: Text("Add the file again if text extraction did not finish.")
            )
        }
    }

    private var chapterNavigation: some View {
        VStack(spacing: 16) {
            Divider().overlay(theme.foreground.opacity(0.15))
            HStack {
                Button {
                    moveChapter(by: -1)
                } label: {
                    Label("Previous chapter", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("[", modifiers: .command)
                .disabled(currentChapterIndex <= 0)

                Spacer()

                VStack(spacing: 5) {
                    ProgressView(value: readingProgress)
                        .frame(width: 160)
                    Text(verbatim: "\(BookLensLocalization.string("Read")) \(Int(readingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(theme.foreground.opacity(0.65))
                }

                Spacer()

                Button {
                    moveChapter(by: 1)
                } label: {
                    Label("Next chapter", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("]", modifiers: .command)
                .disabled(currentChapterIndex >= chapters.count - 1)
            }
        }
    }

    private var chapters: [ChapterRecord] {
        book.chapters.sorted { $0.index < $1.index }
    }

    private var currentChapter: ChapterRecord? {
        guard let selectedChapterID else { return chapters.first }
        return chapters.first { $0.id == selectedChapterID } ?? chapters.first
    }

    private var currentChapterIndex: Int {
        guard let currentChapter else { return 0 }
        return chapters.firstIndex(where: { $0.id == currentChapter.id }) ?? 0
    }

    private var currentChapterNumber: Int { chapters.isEmpty ? 0 : currentChapterIndex + 1 }

    private var readingProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        return Double(currentChapterNumber) / Double(chapters.count)
    }

    private var searchResults: [ChapterRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.text.localizedCaseInsensitiveContains(query)
        }
    }

    private var design: ReaderFontDesign {
        ReaderFontDesign(rawValue: fontDesign) ?? .serif
    }

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: readerTheme) ?? .system
    }

    private func paragraphs(in chapter: ChapterRecord) -> [String] {
        let paragraphs = chapter.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != chapter.title }
        return paragraphs.isEmpty ? [chapter.text] : paragraphs
    }

    private func moveChapter(by offset: Int) {
        let destination = currentChapterIndex + offset
        guard chapters.indices.contains(destination) else { return }
        selectedChapterID = chapters[destination].id
    }

    private func saveProgress() {
        guard let currentChapter else { return }
        ReaderProgressStore.save(chapterID: currentChapter.id, for: book.id)
    }

    private func searchSnippet(for chapter: ChapterRecord) -> String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let range = chapter.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else { return String(chapter.text.prefix(90)) + (chapter.text.count > 90 ? "…" : "") }
        let start = chapter.text.index(range.lowerBound, offsetBy: -45, limitedBy: chapter.text.startIndex)
            ?? chapter.text.startIndex
        let end = chapter.text.index(range.upperBound, offsetBy: 65, limitedBy: chapter.text.endIndex)
            ?? chapter.text.endIndex
        return String(chapter.text[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }
}

enum ReaderProgressStore {
    static func chapterID(for bookID: UUID) -> UUID? {
        UserDefaults.standard.string(forKey: key(for: bookID)).flatMap(UUID.init(uuidString:))
    }

    static func save(chapterID: UUID, for bookID: UUID) {
        UserDefaults.standard.set(chapterID.uuidString, forKey: key(for: bookID))
    }

    static func progress(for book: BookRecord) -> Double? {
        let chapters = book.chapters.sorted { $0.index < $1.index }
        guard !chapters.isEmpty,
              let chapterID = chapterID(for: book.id),
              let index = chapters.firstIndex(where: { $0.id == chapterID })
        else { return nil }
        return Double(index + 1) / Double(chapters.count)
    }

    private static func key(for bookID: UUID) -> String {
        "reader.progress.\(bookID.uuidString)"
    }
}

private enum ReaderFontDesign: String, CaseIterable, Identifiable {
    case serif
    case sans
    case rounded

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .serif: "Book"
        case .sans: "Modern"
        case .rounded: "Rounded"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }
}

private enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case sepia
    case night

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Use app theme"
        case .sepia: "Sepia"
        case .night: "Night"
        }
    }

    var background: Color {
        switch self {
        case .system: Color(nsColor: .textBackgroundColor)
        case .sepia: Color(red: 0.96, green: 0.91, blue: 0.79)
        case .night: Color(red: 0.075, green: 0.085, blue: 0.10)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .sepia: Color(red: 0.22, green: 0.17, blue: 0.11)
        case .night: Color.white.opacity(0.9)
        }
    }
}

private struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var pageWidth: Double
    @Binding var fontDesign: String
    @Binding var readerTheme: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading settings")
                .font(.headline)

            Picker("Font", selection: $fontDesign) {
                ForEach(ReaderFontDesign.allCases) { design in
                    Text(design.title).tag(design.rawValue)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Text size")
                    Spacer()
                    Text("\(Int(fontSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $fontSize, in: 15...32, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Line spacing")
                Slider(value: $lineSpacing, in: 3...16, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Page width")
                Slider(value: $pageWidth, in: 560...920, step: 20)
            }

            Picker("Background", selection: $readerTheme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }
        }
        .padding(18)
        .frame(width: 330)
    }
}
