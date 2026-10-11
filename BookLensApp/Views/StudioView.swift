import AppKit
import BookLensData
import BookLensDomain
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var books: [BookRecord]
    @Query(sort: \ArtworkRecord.createdAt, order: .reverse) private var artworks: [ArtworkRecord]
    @State private var controller = GenerationController()
    @State private var composition: PortraitComposition = .portrait
    @State private var style: IllustrationStyle = .cinematicRealism
    @State private var aspectRatio = "4:5"
    @State private var lighting = "natural light from historically plausible sources"
    @State private var background = "a readable interior or book-world location with period furniture and objects"
    @State private var mood = "restrained"
    @State private var strictToBook = true
    @State private var artisticAdditions = ""
    @State private var showsPrompt = false
    @State private var showsGenerationConfirmation = false
    @State private var exportError: String?

    var body: some View {
        Group {
            if let character, let book {
                HSplitView {
                    preview(character: character, book: book)
                        .frame(minWidth: 480)
                    controls(character: character, book: book)
                        .frame(minWidth: 360, idealWidth: 410, maxWidth: 480)
                }
            } else {
                ContentUnavailableView {
                    Label("Choose a character", systemImage: "paintbrush.pointed")
                } description: {
                    Text("Open a book, wait for AI analysis, and choose a main character.")
                } actions: {
                    Button("Go to characters") { model.selectedSection = .characters }
                }
            }
        }
        .navigationTitle(BookLensLocalization.string("Generation Studio"))
        .onAppear { applyCreationMode(model.selectedCreationMode) }
        .onChange(of: model.selectedCreationMode) { _, mode in
            applyCreationMode(mode)
        }
        .onChange(of: composition) { _, mode in
            if mode == .bookWorld {
                aspectRatio = "16:9"
            }
        }
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
        .confirmationDialog(
            "Send the prompt to OpenAI and create an image?",
            isPresented: $showsGenerationConfirmation,
            titleVisibility: .visible
        ) {
            if let character, let book {
                Button("Send and create image") {
                    startGeneration(character: character, book: book)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Selected quotes, the character description, book context, and image settings will be sent. The request uses your ChatGPT plan limits.")
        }
    }

    private func preview(character: CharacterRecord, book: BookRecord) -> some View {
        let artworkURL = displayedArtworkURL(for: character.id)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name).font(.largeTitle.bold())
                Text(book.title).foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(BookLensTheme.cardGradient)
                if controller.isRunning {
                    AIGenerationProgressView(
                        state: controller.state,
                        status: controller.statusText,
                        startedAt: controller.startedAt,
                        finishedAt: controller.finishedAt
                    )
                } else if let artworkURL,
                   let image = NSImage(contentsOf: artworkURL)
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(10)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "person.crop.artframe")
                            .font(.system(size: 72))
                            .foregroundStyle(BookLensTheme.accent)
                        Text(verbatim: controller.statusText)
                            .font(.title3.weight(.medium))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.1))
            }

            if let artworkURL {
                HStack(spacing: 12) {
                    Label("Automatically saved to the BookLens gallery", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    if let duration = controller.completedDuration {
                        Label {
                            Text(verbatim: "\(BookLensLocalization.string("Created in")) \(AIElapsedTimeView.formattedDuration(seconds: duration))")
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let artwork = displayedArtworkRecord(for: character.id) {
                        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
                            openWindow(value: artwork.id)
                        }
                        Button(
                            book.coverArtworkID == artwork.id ? "Restore original cover" : "Make book cover",
                            systemImage: book.coverArtworkID == artwork.id ? "arrow.uturn.backward" : "book.closed.fill"
                        ) {
                            toggleBookCover(artwork, for: book)
                        }
                    }
                    Button("Open gallery") {
                        model.selectedSection = .gallery
                    }
                    Button("Save photo…", systemImage: "square.and.arrow.down") {
                        savePhoto(from: artworkURL, character: character, book: book)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .bookLensCard()
            }

            if let error = controller.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(error.localizedDescription)
                        Text(error.diagnosticCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Retry") { controller.resetForRetry() }
                }
                .padding(12)
                .bookLensCard()
            }
        }
        .padding(24)
    }

    private func controls(character: CharacterRecord, book: BookRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Composition").font(.headline)
                Picker("Composition", selection: $composition) {
                    Text("Portrait").tag(PortraitComposition.portrait)
                    Text("Waist up").tag(PortraitComposition.waistUp)
                    Text("Full body").tag(PortraitComposition.fullBody)
                    Text("In a scene").tag(PortraitComposition.scene)
                    Text("Book world").tag(PortraitComposition.bookWorld)
                }
                .pickerStyle(.segmented)

                if composition == .bookWorld {
                    Label(
                        "A complete wide illustration with the important characters, a key location, and recognizable objects from the book.",
                        systemImage: "person.3.sequence.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Picker("Aspect ratio", selection: $aspectRatio) {
                    Text("1:1").tag("1:1")
                    Text("4:5").tag("4:5")
                    Text("3:2").tag("3:2")
                    Text("16:9").tag("16:9")
                }

                Divider()
                modelControls

                Divider()
                Text("Art direction").font(.headline)
                Picker("Style", selection: $style) {
                    Text("Cinematic realism").tag(IllustrationStyle.cinematicRealism)
                    Text("Classic book illustration").tag(IllustrationStyle.classicBookIllustration)
                    Text("Engraving").tag(IllustrationStyle.engraving)
                    Text("Watercolor").tag(IllustrationStyle.watercolor)
                    Text("Graphic novel").tag(IllustrationStyle.graphicNovel)
                    Text("Atmospheric painting").tag(IllustrationStyle.atmosphericPainting)
                    Text("Studio portrait").tag(IllustrationStyle.neutralStudioPortrait)
                }
                TextField("Lighting", text: $lighting)
                TextField("Background", text: $background)
                TextField("Mood", text: $mood)
                Toggle("Strictly follow the book", isOn: $strictToBook)
                TextField("Explicit artistic additions", text: $artisticAdditions, axis: .vertical)
                    .lineLimit(3...6)

                Divider()
                evidenceSummary(character)

                Button("Preview the generated prompt") {
                    updatePromptPreview(character: character, book: book)
                    showsPrompt = true
                }
                .sheet(isPresented: $showsPrompt) {
                    PromptPreviewSheet(prompt: controller.promptPreview)
                        .environment(\.locale, model.preferredLocale)
                }

                HStack {
                    if controller.isRunning {
                        Button("Cancel", role: .destructive) { controller.cancel() }
                            .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button(controller.state == .failed ? "Retry" : "Create image") {
                        updatePromptPreview(character: character, book: book)
                        showsGenerationConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(controller.isRunning || !canGenerate(character) || !model.canUseAI)
                }
            }
            .padding(24)
        }
    }

    private func evidenceSummary(_ character: CharacterRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile evidence").font(.headline)
            ForEach(character.traits) { trait in
                HStack(alignment: .top) {
                    Image(systemName: trait.evidenceIDs.isEmpty ? "exclamationmark.triangle" : "checkmark.seal.fill")
                        .foregroundStyle(trait.evidenceIDs.isEmpty ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trait.category): \(trait.value)")
                        Text(verbatim: "\(confidenceTitle(trait.confidence)) · \(BookLensLocalization.string("Sources")): \(trait.evidenceIDs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .bookLensCard()
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model and reasoning").font(.headline)
                Spacer()
                Text(model.modelCatalogIsLive ? "live catalog" : "pinned fallback")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("Model", selection: Binding(
                get: { model.selectedModelID },
                set: { model.selectModel($0) }
            )) {
                ForEach(model.modelOptions) { option in
                    Text(verbatim: option.displayName).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("studioModelPicker")

            Picker("Reasoning", selection: Binding(
                get: { model.selectedReasoningEffort },
                set: { model.selectReasoningEffort($0) }
            )) {
                ForEach(model.reasoningOptions) { option in
                    Text(LocalizedStringKey(reasoningLabel(option.value))).tag(option.value)
                }
            }
            Text(verbatim: "\(model.selectedModel?.displayName ?? model.selectedModelID) · \(BookLensLocalization.string("Reasoning")): \(model.selectedReasoningEffort)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if GenerationController.optimizedReasoningEffort(model.selectedReasoningEffort) != model.selectedReasoningEffort {
                Label(
                    "Image generation is automatically capped at medium reasoning for faster results without weakening the book prompt.",
                    systemImage: "speedometer"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var character: CharacterRecord? {
        guard let id = model.selectedCharacterID else { return nil }
        return books.flatMap(\.characters).first { $0.id == id }
    }

    private var book: BookRecord? {
        guard let id = model.selectedBookID else { return character?.book }
        return books.first { $0.id == id }
    }

    private func canGenerate(_ character: CharacterRecord) -> Bool {
        !character.traits.isEmpty
    }

    private func request(character: CharacterRecord, book: BookRecord) -> GenerationRequest {
        let traits = character.traits.compactMap { record -> CharacterTrait? in
            guard let confidence = TraitConfidence(rawValue: record.confidence) else { return nil }
            return CharacterTrait(
                id: record.id,
                category: record.category,
                value: record.value,
                confidence: confidence,
                evidenceIDs: record.evidenceIDs
            )
        }
        let evidenceRecords = book.chapters.flatMap(\.evidence)
        let ids = Set(traits.flatMap(\.evidenceIDs))
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidenceRecords
            .filter { ids.contains($0.id) }
            .map { ($0.id, $0.text) })
        let profile = CharacterProfileSnapshot(
            characterID: character.id,
            characterName: character.name,
            traits: traits
        )
        return GenerationRequest(
            bookID: book.id,
            bookTitle: book.title,
            bookAuthor: book.author,
            bookSynopsis: book.synopsis,
            importantCharacters: importantCharacters(in: book, selectedCharacterID: character.id),
            characterID: character.id,
            profile: profile,
            evidenceByID: evidenceByID,
            settings: GenerationSettings(
                composition: composition,
                style: style,
                aspectRatio: aspectRatio,
                lighting: lighting,
                background: background,
                mood: mood,
                strictToBook: strictToBook,
                artisticAdditions: artisticAdditions
            ),
            references: [],
            modelID: model.selectedModelID,
            reasoningEffort: model.selectedReasoningEffort
        )
    }

    private func updatePromptPreview(character: CharacterRecord, book: BookRecord) {
        let request = request(character: character, book: book)
        let previewPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLens-Preview/output", isDirectory: true)
        controller.preparePrompt(request, outputDirectory: previewPath)
    }

    private func startGeneration(character: CharacterRecord, book: BookRecord) {
        guard model.canUseAI, let storage = model.storage else { return }
        let request = request(character: character, book: book)
        controller.generate(request: request, storage: storage) { result in
            modelContext.insert(
                ArtworkRecord(
                    id: result.artwork.id,
                    jobID: result.artwork.jobID,
                    characterID: result.artwork.characterID,
                    bookID: book.id,
                    filename: result.artwork.filename,
                    storedPath: result.storedURL.path,
                    sha256: result.artwork.sha256,
                    pixelWidth: result.artwork.pixelWidth,
                    pixelHeight: result.artwork.pixelHeight,
                    style: result.style,
                    composition: composition.rawValue
                )
            )
            try? modelContext.save()
        }
    }

    private func displayedArtworkURL(for characterID: UUID) -> URL? {
        // A previous image must not cover progress while a new variation is running.
        guard !controller.isRunning else { return nil }
        if let generated = controller.generated, generated.artwork.characterID == characterID {
            return generated.storedURL
        }
        guard let artwork = artworks.first(where: { $0.characterID == characterID }) else { return nil }
        return URL(fileURLWithPath: artwork.storedPath)
    }

    private func displayedArtworkRecord(for characterID: UUID) -> ArtworkRecord? {
        if let generated = controller.generated,
           generated.artwork.characterID == characterID,
           let record = artworks.first(where: { $0.id == generated.artwork.id })
        {
            return record
        }
        return artworks.first { $0.characterID == characterID }
    }

    private func toggleBookCover(_ artwork: ArtworkRecord, for book: BookRecord) {
        book.coverArtworkID = book.coverArtworkID == artwork.id ? nil : artwork.id
        try? modelContext.save()
    }

    private func savePhoto(from source: URL, character: CharacterRecord, book: BookRecord) {
        let fileExtension = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let panel = NSSavePanel()
        panel.title = BookLensLocalization.string("Save photo")
        panel.nameFieldStringValue = "\(safeFilename(book.title))-\(safeFilename(character.name)).\(fileExtension)"
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: fileExtension) {
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

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let result = pieces.joined(separator: "-")
        return result.isEmpty ? "BookLens" : result
    }

    private func reasoningLabel(_ value: String) -> String {
        switch value {
        case "low": "Fast"
        case "medium": "Balanced"
        case "high": "Deep"
        case "xhigh": "Very deep"
        case "max": "Maximum"
        case "ultra": "Ultra"
        default: value
        }
    }

    private func confidenceTitle(_ value: String) -> String {
        switch value {
        case "confirmed": BookLensLocalization.string("Confirmed")
        case "probable": BookLensLocalization.string("Probable")
        case "unspecified": BookLensLocalization.string("Not specified")
        default: value
        }
    }

    private func applyCreationMode(_ mode: CharacterCreationMode) {
        switch mode {
        case .portrait: composition = .portrait
        case .fullBody: composition = .fullBody
        case .scene: composition = .scene
        case .bookWorld:
            composition = .bookWorld
            aspectRatio = "16:9"
        }
    }

    private func importantCharacters(in book: BookRecord, selectedCharacterID: UUID) -> [String] {
        book.characters
            .filter { $0.isMainCharacter && !$0.isExcluded }
            .sorted { lhs, rhs in
                if lhs.id == selectedCharacterID { return true }
                if rhs.id == selectedCharacterID { return false }
                if lhs.occurrenceCount == rhs.occurrenceCount { return lhs.name < rhs.name }
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
            .prefix(6)
            .map { character in
                [character.name, character.role, character.summary]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " — ")
            }
    }
}

private struct PromptPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generated prompt").font(.title2.bold())
            Text("This text will be sent to Codex. BookLens does not save it in logs.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(prompt)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .bookLensCard()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 650)
    }
}
