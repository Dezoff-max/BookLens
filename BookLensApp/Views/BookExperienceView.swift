import BookLensCodex
import BookLensData
import Foundation
import SwiftData
import SwiftUI

struct BookExperienceView: View {
    @Bindable var model: AppModel
    @Bindable var book: BookRecord
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @State private var analysis = BookAnalysisController()
    @State private var showsClassificationEditor = false
    @State private var showsAnalysisConfirmation = false
    @State private var pendingAnalysisIsRefresh = false

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 16)]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    bookHeader
                    analysisState
                    characterGrid
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .navigationTitle(book.title)
        .task(id: book.id) {
            await repairEPUBMetadataIfNeeded()
            recoverInterruptedAnalysisIfNeeded()
        }
        .sheet(isPresented: $showsClassificationEditor) {
            BookClassificationEditor(book: book)
                .environment(\.locale, model.preferredLocale)
        }
    }

    private var bookHeader: some View {
        HStack(alignment: .top, spacing: 22) {
            BookCoverView(
                book: book,
                artwork: preferredCoverArtwork(for: book, from: artworks),
                cornerRadius: 12
            )
                .frame(width: 112, height: 156)

            VStack(alignment: .leading, spacing: 9) {
                Button {
                    model.selectedBookID = nil
                } label: {
                    Label("All books", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(BookLensTheme.accent)

                Text(book.title)
                    .font(.largeTitle.bold())
                Text(book.author)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    BookClassificationBadges(book: book, maximumGenres: 3)
                    Button("Edit", systemImage: "slider.horizontal.3") {
                        showsClassificationEditor = true
                    }
                    .buttonStyle(.borderless)
                }

                if !book.synopsis.isEmpty {
                    Text(book.synopsis)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                } else {
                    Text("A short spoiler-free synopsis will appear here after AI analysis.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var analysisState: some View {
        if analysis.isAnalyzing || book.analysisStatus == "analyzing" {
            VStack(spacing: 14) {
                AIBookAnalysisProgressView(
                    status: analysis.statusText,
                    startedAt: analysis.startedAt,
                    finishedAt: analysis.finishedAt
                )
                Button("Stop", role: .destructive) { analysis.cancel() }
                    .controlSize(.large)
            }
            .padding(24)
            .bookLensCard()
        } else if case let .failed(message) = analysis.state {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Couldn’t identify the characters").font(.headline)
                    Text(message).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Retry analysis") { requestAnalysis(force: true) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .bookLensCard()
        } else if mainCharacters.isEmpty {
            HStack(spacing: 16) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 30))
                    .foregroundStyle(BookLensTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find main characters")
                        .font(.headline)
                    Text("AI will understand the story, discard false names, and prepare descriptions for image generation.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Analyze book") { requestAnalysis(force: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canUseAI)
            }
            .padding(18)
            .bookLensCard()
        }
    }

    private var characterGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Main characters")
                        .font(.title2.bold())
                    Text(verbatim: BookLensLocalization.string(mainCharacters.isEmpty ? "They will appear after AI analysis" : "Choose a character, then create a portrait, full-body image, scene, or book world"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let duration = analysis.completedDuration {
                    Label {
                        Text(verbatim: "\(BookLensLocalization.string("Analysis")): \(AIElapsedTimeView.formattedDuration(seconds: duration))")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !mainCharacters.isEmpty, book.sourceKind == "local" {
                    Button("Refresh analysis", systemImage: "arrow.clockwise") {
                        requestAnalysis(force: true)
                    }
                    .disabled(analysis.isAnalyzing || !model.canUseAI)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(mainCharacters) { character in
                    CharacterVisualCard(
                        character: character,
                        artwork: latestArtwork(for: character.id),
                        isSelected: model.selectedCharacterID == character.id
                    ) {
                        model.selectedCharacterID = character.id
                    }
                }
            }
        }
        .confirmationDialog(
            "Send selected excerpts to OpenAI?",
            isPresented: $showsAnalysisConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send and analyze") {
                startAnalysis(force: pendingAnalysisIsRefresh)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(verbatim: String(
                format: BookLensLocalization.string("BookLens will send the title, author, headings, and %lld characters of selected text. The original file is not sent. The request uses your ChatGPT plan limits."),
                Int64(analysisPayloadCharacterCount)
            ))
        }
    }

    private var mainCharacters: [CharacterRecord] {
        book.characters
            .filter { $0.isMainCharacter && !$0.isExcluded }
            .sorted { lhs, rhs in
                if lhs.occurrenceCount == rhs.occurrenceCount { return lhs.name < rhs.name }
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
    }

    private var selectedCharacter: CharacterRecord? {
        guard let id = model.selectedCharacterID else { return nil }
        return mainCharacters.first { $0.id == id }
    }

    private func latestArtwork(for characterID: UUID) -> ArtworkRecord? {
        artworks.first { $0.characterID == characterID }
    }

    private func recoverInterruptedAnalysisIfNeeded() {
        guard book.sourceKind == "local",
              book.analysisStatus == "analyzing",
              !analysis.isAnalyzing
        else { return }
        book.analysisStatus = "pending"
        try? modelContext.save()
    }

    private func startAnalysis(force: Bool) {
        guard book.sourceKind == "local", !analysis.isAnalyzing, model.canUseAI else { return }
        if force { book.analysisStatus = "pending" }
        analysis.analyze(book: book, model: model, modelContext: modelContext)
    }

    private func requestAnalysis(force: Bool) {
        guard model.canUseAI else { return }
        pendingAnalysisIsRefresh = force
        showsAnalysisConfirmation = true
    }

    private var analysisPayloadCharacterCount: Int {
        let chapters = book.chapters
            .sorted { $0.index < $1.index }
            .map { BookAnalysisChapter(title: $0.title, text: $0.text) }
        return BookAnalysisService.makeRepresentativeExcerpt(from: chapters).count
    }

    private func repairEPUBMetadataIfNeeded() async {
        guard book.sourceKind == "local",
              book.sourceFilename.pathExtension.lowercased() == "epub",
              !book.storedSourcePath.isEmpty
        else { return }

        let filenameTitle = book.sourceFilename.deletingPathExtension
        let shouldRepairTitle = book.title == filenameTitle
        let normalizedAuthor = normalizedMetadata(book.author)
        let shouldRepairAuthor = book.author == "Author not specified" || normalizedAuthor != book.author
        guard shouldRepairTitle || shouldRepairAuthor else { return }

        let sourceURL = URL(fileURLWithPath: book.storedSourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              let extracted = try? await EPUBExtractor().extract(from: sourceURL)
        else { return }

        var changed = false
        if shouldRepairTitle, let title = normalizedMetadata(extracted.title), !title.isEmpty {
            book.title = title
            changed = true
        }
        if let author = normalizedMetadata(extracted.author),
           !author.isEmpty,
           (book.author == "Author not specified" || normalizedAuthor == author)
        {
            book.author = author
            changed = true
        }
        if book.language == nil, let language = normalizedMetadata(extracted.language), !language.isEmpty {
            book.language = language
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
    var deletingPathExtension: String { (self as NSString).deletingPathExtension }
}
