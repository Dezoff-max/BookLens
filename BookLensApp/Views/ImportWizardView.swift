import BookLensData
import BookLensDomain
import BookLensSupport
import Observation
import SwiftUI

struct ImportWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: ImportWizardState
    let onComplete: (ImportedBook) -> Void

    init(sourceURL: URL, pipeline: BookImportPipeline, onComplete: @escaping (ImportedBook) -> Void) {
        _state = State(initialValue: ImportWizardState(sourceURL: sourceURL, pipeline: pipeline))
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import book")
                        .font(.title2.bold())
                    Text(state.sourceURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Close") {
                    state.cancel()
                    dismiss()
                }
            }

            if state.isRunning || state.result != nil {
                progressContent
            } else {
                Form {
                    TextField("Title (optional)", text: $state.title)
                    TextField("Author (optional)", text: $state.author)
                    LabeledContent("Format", value: state.sourceURL.pathExtension.uppercased())
                    LabeledContent("Original", value: "will remain unchanged")
                    Text("For EPUB files, the title and author are read automatically from the book.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }

            if let error = state.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(12)
                    .bookLensCard()
            }

            HStack {
                if state.isRunning {
                    Button("Cancel", role: .destructive) { state.cancel() }
                }
                Spacer()
                if let result = state.result {
                    Button("Continue — find main characters") {
                        onComplete(result)
                    }
                        .buttonStyle(.borderedProminent)
                } else if !state.isRunning {
                    Button("Import") { state.start() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 610, height: 520)
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: state.progressFraction)
            ForEach(ImportStage.allCases, id: \.rawValue) { stage in
                HStack {
                    Image(systemName: state.icon(for: stage))
                        .foregroundStyle(state.color(for: stage))
                        .frame(width: 18)
                    Text(state.label(for: stage))
                    Spacer()
                }
                .foregroundStyle(state.isReached(stage) ? .primary : .secondary)
            }
            if let result = state.result {
                Divider()
                LabeledContent("Chapters", value: String(result.chapters.count))
                Label {
                    Text("The text is ready. AI will now understand the story, identify the main characters, and prepare their descriptions.")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .bookLensCard()
            }
        }
        .padding(18)
        .bookLensCard()
    }
}

@MainActor
@Observable
private final class ImportWizardState {
    let sourceURL: URL
    var title: String
    var author = ""
    var stage: ImportStage = .validating
    var isRunning = false
    var result: ImportedBook?
    var error: Error?

    private let pipeline: BookImportPipeline
    private var task: Task<Void, Never>?

    init(sourceURL: URL, pipeline: BookImportPipeline) {
        self.sourceURL = sourceURL
        self.pipeline = pipeline
        title = ""
    }

    var progressFraction: Double {
        guard let index = ImportStage.allCases.firstIndex(of: stage) else { return 0 }
        return Double(index + 1) / Double(ImportStage.allCases.count)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        result = nil
        let sourceURL = sourceURL
        let title = title
        let author = author
        let pipeline = pipeline
        task = Task {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let imported = try await pipeline.importBook(
                    from: sourceURL,
                    title: title,
                    author: author
                ) { [weak self] stage in
                    Task { @MainActor in self?.stage = stage }
                }
                result = imported
            } catch {
                self.error = error
            }
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func isReached(_ candidate: ImportStage) -> Bool {
        guard let current = ImportStage.allCases.firstIndex(of: stage),
              let other = ImportStage.allCases.firstIndex(of: candidate)
        else { return false }
        return other <= current
    }

    func icon(for candidate: ImportStage) -> String {
        if result != nil || (isReached(candidate) && candidate != stage) {
            return "checkmark.circle.fill"
        }
        if candidate == stage, isRunning {
            return "arrow.triangle.2.circlepath"
        }
        return "circle"
    }

    func color(for candidate: ImportStage) -> Color {
        isReached(candidate) ? BookLensTheme.accent : .secondary
    }

    func label(for stage: ImportStage) -> String {
        switch stage {
        case .validating: "Validating type and text layer"
        case .copying: "Copying to Application Support"
        case .extracting: "Extracting text"
        case .splittingChapters: "Splitting chapters"
        case .normalizing: "Normalizing"
        case .indexing: "Building local index"
        case .findingNames: "Preparing text for AI"
        case .finished: "Complete"
        }
    }
}
