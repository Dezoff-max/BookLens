import BookLensCodex
import BookLensData
import BookLensSupport
import SwiftData
import SwiftUI

struct WebBookSearchView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var query: String
    @State private var isSearching = false
    @State private var result: BookAnalysisResult?
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    init(model: AppModel, initialQuery: String = "") {
        self.model = model
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: localized("Find a book and its characters"))
                        .font(.title2.bold())
                    Text(verbatim: localized("Enter a title, author, or character — AI will find reliable book sources."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Close")) { dismiss() }
            }

            HStack(spacing: 10) {
                TextField(localized("For example: War and Peace Leo Tolstoy"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onSubmit { search() }
                Button(localized("Search")) { search() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedQuery.isEmpty || isSearching || !model.canUseAI)
            }

            if isSearching {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(verbatim: localized("AI is finding the book, checking the author, and gathering the main characters…"))
                        .font(.headline)
                    Text(verbatim: localized("Full texts are not downloaded. Only short excerpts from public sources are used."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                resultContent(result)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(localized("Book not found"), systemImage: "magnifyingglass")
                } description: {
                    Text(verbatim: errorMessage)
                } actions: {
                    Button(localized("Try again")) { search() }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(BookLensTheme.accent)
                    Text(verbatim: localized("No book file required"))
                        .font(.title3.bold())
                    Text(verbatim: localized("BookLens will find the synopsis and main characters, and show the sources before adding the book."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(width: 780, height: 680)
        .onDisappear { task?.cancel() }
    }

    private func resultContent(_ result: BookAnalysisResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverPlaceholder(title: result.bookTitle)
                        .frame(width: 88, height: 124)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.bookTitle).font(.title2.bold())
                        Text(result.author).foregroundStyle(.secondary)
                        Text(result.synopsis).lineLimit(5)
                    }
                    Spacer()
                }

                Text(verbatim: localized("Main characters")).font(.headline)
                ForEach(result.characters, id: \.name) { character in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(BookLensTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(character.name).fontWeight(.semibold)
                            Text(character.role).font(.caption).foregroundStyle(.secondary)
                            Text(character.description).font(.callout).lineLimit(3)
                        }
                    }
                    .padding(12)
                    .bookLensCard()
                }

                if !result.sources.isEmpty {
                    DisclosureGroup("\(localized("Sources")) · \(result.sources.count)") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(result.sources, id: \.url) { source in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title).fontWeight(.medium)
                                    Text(source.url)
                                        .font(.caption)
                                        .foregroundStyle(BookLensTheme.accent)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                HStack {
                    Button(localized("Search again")) {
                        self.result = nil
                    }
                    Spacer()
                    Button(localized("Add book and choose a character")) {
                        save(result)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(4)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localized(_ key: String) -> String {
        BookLensLocalization.string(key)
    }

    private func search() {
        guard !trimmedQuery.isEmpty, !isSearching else { return }
        isSearching = true
        result = nil
        errorMessage = nil
        let query = trimmedQuery
        let modelID = model.selectedModelID
        let effort = model.selectedReasoningEffort
        let outputLanguage = model.analysisOutputLanguage
        task = Task {
            do {
                let workingDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BookLens-Web-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: workingDirectory) }
                result = try await BookAnalysisService().discoverBook(
                    query: query,
                    workingDirectory: workingDirectory,
                    modelID: modelID,
                    reasoningEffort: effort,
                    outputLanguage: outputLanguage
                )
            } catch let error as BookLensError {
                if case .timeout = error {
                    errorMessage = BookLensLocalization.string("The search took longer than usual. Try again — BookLens will now wait for AI to finish checking the sources.")
                } else {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = BookLensLocalization.string("Check the query and connection, then try again.")
            }
            isSearching = false
        }
    }

    private func save(_ result: BookAnalysisResult) {
        let record = BookAnalysisController.makeWebBook(from: result)
        modelContext.insert(record)
        try? modelContext.save()
        model.selectedBookID = record.id
        model.selectedCharacterID = record.characters.first?.id
        model.selectedSection = .library
        dismiss()
    }
}
