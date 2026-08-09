import BookLensData
import BookLensSupport
import SwiftData
import SwiftUI

struct BookWorkspaceView: View {
    @Bindable var model: AppModel
    @Bindable var book: BookRecord
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCharacterID: UUID?
    @State private var selectedEvidenceIDs: Set<UUID> = []
    @State private var tab: CharacterTab = .profile
    @State private var isAddingCharacter = false
    @State private var isAddingTrait = false
    @State private var isMergingAliases = false
    @State private var isSearchingMentions = false
    @State private var searchNotice: String?
    @State private var isShowingExtractedText = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            HSplitView {
                characterColumn
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 290, maxHeight: .infinity)
                evidenceColumn
                    .frame(minWidth: 300, idealWidth: 430, maxHeight: .infinity)
                profileColumn
                    .frame(minWidth: 280, idealWidth: 350, maxWidth: 470, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(book.title)
        .task {
            let preferred = model.selectedCharacterID.flatMap { id in
                book.characters.first(where: { $0.id == id && !$0.isExcluded })?.id
            }
            selectedCharacterID = preferred ?? activeCharacters.first?.id
            model.selectedCharacterID = selectedCharacterID
        }
        .onChange(of: selectedCharacterID) { _, newValue in
            model.selectedCharacterID = newValue
            selectedEvidenceIDs = []
        }
        .sheet(isPresented: $isAddingCharacter) {
            AddCharacterSheet { name in
                addCharacterAndFindMentions(named: name)
            }
            .environment(\.locale, model.preferredLocale)
        }
        .sheet(isPresented: $isAddingTrait) {
            if let character = selectedCharacter {
                TraitEditorSheet(
                    evidence: selectedEvidence,
                    onSave: { category, value, confidence in
                        character.traits.append(
                            TraitRecord(
                                category: category,
                                value: value,
                                confidence: confidence,
                                evidenceIDs: Array(selectedEvidenceIDs)
                            )
                        )
                        try? modelContext.save()
                    }
                )
                .environment(\.locale, model.preferredLocale)
            }
        }
        .sheet(isPresented: $isMergingAliases) {
            if let character = selectedCharacter {
                MergeAliasesSheet(target: character, candidates: activeCharacters.filter { $0.id != character.id }) { source in
                    character.aliases = Array(Set(character.aliases + source.aliases + [source.name])).sorted()
                    for evidence in book.chapters.flatMap(\.evidence) where evidence.characterName == source.name {
                        evidence.characterName = character.name
                    }
                    source.isExcluded = true
                    book.characterCount = activeCharacters.filter { $0.id != source.id }.count
                    try? modelContext.save()
                }
                .environment(\.locale, model.preferredLocale)
            }
        }
        .sheet(isPresented: $isShowingExtractedText) {
            ExtractedTextPreview(chapters: book.chapters.sorted { $0.index < $1.index })
                .environment(\.locale, model.preferredLocale)
        }
    }

    private var workspaceHeader: some View {
        HStack {
            Button {
                model.selectedBookID = nil
                model.selectedCharacterID = nil
            } label: {
                Label("Library", systemImage: "chevron.left")
            }

            Divider().frame(height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.headline)
                HStack(spacing: 8) {
                    Text(workspaceSummary)
                    Label("Text extracted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.caption)
            }
            Spacer()
            if isSearchingMentions {
                ProgressView()
                    .controlSize(.small)
                Text("Finding mentions…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectedCharacter != nil, activeCharacters.count >= 2 {
                Button {
                    isMergingAliases = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
            }

            Button {
                isAddingCharacter = true
            } label: {
                Label("Add name", systemImage: "person.badge.plus")
            }
            .disabled(isSearchingMentions)
        }
        .padding(14)
    }

    private var characterColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Characters")
                .font(.headline)
                .padding(14)
            Divider()
            if activeCharacters.isEmpty {
                emptyCharacterColumn
            } else {
                if let searchNotice {
                    Text(searchNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
                List(selection: $selectedCharacterID) {
                    ForEach(activeCharacters) { character in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(character.name)
                            Text("\(character.occurrenceCount) mentions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(character.id)
                        .contextMenu {
                            Button("Exclude false match", role: .destructive) {
                                character.isExcluded = true
                                if selectedCharacterID == character.id {
                                    selectedCharacterID = activeCharacters.first(where: { $0.id != character.id })?.id
                                }
                                book.characterCount = max(0, activeCharacters.count - 1)
                                try? modelContext.save()
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var evidenceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Excerpts and context").font(.headline)
                    Text("Only selected excerpts will be sent to Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select all") {
                    selectedEvidenceIDs = Set(evidence.map(\.id))
                }
                .disabled(evidence.isEmpty)
            }
            .padding(14)
            Divider()

            if selectedCharacter == nil {
                noCharacterEvidenceState
            } else if evidence.isEmpty {
                ContentUnavailableView(
                    "No mentions found",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try adding the full name or another spelling. The book text has already been extracted locally.")
                )
            } else {
                List(evidence) { item in
                    Toggle(isOn: Binding(
                        get: { selectedEvidenceIDs.contains(item.id) },
                        set: { isOn in
                            if isOn { selectedEvidenceIDs.insert(item.id) }
                            else { selectedEvidenceIDs.remove(item.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.chapter?.title ?? "Section")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BookLensTheme.accent)
                            Text(item.text)
                                .font(.body)
                                .lineLimit(7)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var profileColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let character = selectedCharacter {
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name)
                        .font(.title2.bold())
                    if !character.aliases.isEmpty {
                        Text("Also: \(character.aliases.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                Divider()

                Picker("Section", selection: $tab) {
                    ForEach(CharacterTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                tabContent(character)

                Divider()
                HStack {
                    Button("Add trait") { isAddingTrait = true }
                        .disabled(selectedEvidenceIDs.isEmpty)
                    Spacer()
                    Button("Open Studio") {
                        model.selectedSection = .studio
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate(character))
                }
                .padding(12)
            } else {
                gettingStartedProfile
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ character: CharacterRecord) -> some View {
        switch tab {
        case .profile:
            if character.traits.isEmpty {
                ContentUnavailableView(
                    "Profile not confirmed yet",
                    systemImage: "checkmark.seal",
                    description: Text("Select an excerpt and add a trait. Confirmed and probable traits cannot be saved without supporting excerpts.")
                )
            } else {
                List(character.traits) { trait in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(trait.category).fontWeight(.semibold)
                            Spacer()
                            ConfidenceBadge(value: trait.confidence)
                        }
                        Text(trait.value)
                        Text(verbatim: "\(BookLensLocalization.string("Sources")): \(trait.evidenceIDs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Remove trait", role: .destructive) {
                            modelContext.delete(trait)
                            try? modelContext.save()
                        }
                    }
                }
            }
        case .evidence:
            List(evidence) { item in
                Text(item.text).lineLimit(5)
            }
        case .images:
            ContentUnavailableView("No images yet", systemImage: "photo")
        case .scenes:
            ContentUnavailableView("Scenes will appear later", systemImage: "theatermasks")
        case .history:
            ContentUnavailableView("History is empty", systemImage: "clock.arrow.circlepath")
        }
    }

    private var activeCharacters: [CharacterRecord] {
        book.characters.filter { !$0.isExcluded }.sorted { $0.name < $1.name }
    }

    private var selectedCharacter: CharacterRecord? {
        guard let selectedCharacterID else { return nil }
        return book.characters.first { $0.id == selectedCharacterID }
    }

    private var evidence: [EvidenceRecord] {
        guard let name = selectedCharacter?.name else { return [] }
        return book.chapters
            .sorted { $0.index < $1.index }
            .flatMap(\.evidence)
            .filter { $0.characterName == name }
    }

    private var selectedEvidence: [EvidenceRecord] {
        evidence.filter { selectedEvidenceIDs.contains($0.id) }
    }

    private var workspaceSummary: String {
        let source = URL(fileURLWithPath: book.sourceFilename).pathExtension.uppercased()
        let names = activeCharacters.isEmpty ? "no names found" : "\(activeCharacters.count) characters"
        return "\(source) · \(book.chapterCount) sections · \(chapterTextCharacterCount.formatted()) characters · \(names)"
    }

    private var chapterTextCharacterCount: Int {
        book.chapters.reduce(0) { $0 + $1.text.count }
    }

    private var emptyCharacterColumn: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(BookLensTheme.accent)
            Text("No names found automatically")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("The PDF is valid: \(chapterTextCharacterCount.formatted()) characters were extracted. Enter a character name and BookLens will find mentions locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add name") {
                isAddingCharacter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
    }

    private var noCharacterEvidenceState: some View {
        ContentUnavailableView {
            Label("PDF text is ready", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Extracted \(book.chapterCount) sections and \(chapterTextCharacterCount.formatted()) characters. Add a character name to find real excerpts.")
        } actions: {
            HStack {
                Button("Add name and find mentions") {
                    isAddingCharacter = true
                }
                .buttonStyle(.borderedProminent)
                Button("View text") {
                    isShowingExtractedText = true
                }
            }
        }
    }

    private var gettingStartedProfile: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Next steps", systemImage: "list.number")
                .font(.title3.bold())
            stepRow(number: 1, text: "Add a character name")
            stepRow(number: 2, text: "Select the found excerpts")
            stepRow(number: 3, text: "Add a confirmed trait")
            Button("Add name") {
                isAddingCharacter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(number))
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(BookLensTheme.accent.opacity(0.15), in: Circle())
                .foregroundStyle(BookLensTheme.accent)
            Text(text)
                .font(.callout)
        }
    }

    private func addCharacterAndFindMentions(named name: String) {
        if let existing = activeCharacters.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            selectedCharacterID = existing.id
            searchNotice = "This name has already been added."
            return
        }

        isSearchingMentions = true
        searchNotice = nil
        let chapterRecords = book.chapters.sorted { $0.index < $1.index }
        let extractedChapters = chapterRecords.map { ExtractedChapter(title: $0.title, text: $0.text) }

        Task {
            let candidate = await Task.detached(priority: .userInitiated) {
                CharacterMentionFinder().find(name: name, in: extractedChapters)
            }.value

            let record = CharacterRecord(name: name, occurrenceCount: candidate.occurrenceCount)
            book.characters.append(record)
            for found in candidate.evidence where found.chapterIndex < chapterRecords.count {
                chapterRecords[found.chapterIndex].evidence.append(
                    EvidenceRecord(
                        id: found.id,
                        characterName: name,
                        text: found.excerpt,
                        rangeStart: found.localRange.lowerBound,
                        rangeEnd: found.localRange.upperBound,
                        digest: SHA256Digest.string(for: found.excerpt)
                    )
                )
            }
            book.characterCount = book.characters.filter { !$0.isExcluded }.count
            try? modelContext.save()
            selectedCharacterID = record.id
            searchNotice = candidate.occurrenceCount == 0
                ? "The name was added, but no exact matches were found. Try another spelling."
                : "Found \(candidate.occurrenceCount) mentions."
            isSearchingMentions = false
        }
    }

    private func canGenerate(_ character: CharacterRecord) -> Bool {
        character.traits.contains { trait in
            (trait.confidence == "confirmed" || trait.confidence == "probable")
                && !trait.evidenceIDs.isEmpty
        }
    }
}

private enum CharacterTab: String, CaseIterable, Identifiable {
    case profile, evidence, images, scenes, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .profile: "Profile"
        case .evidence: "Sources"
        case .images: "Images"
        case .scenes: "Scenes"
        case .history: "History"
        }
    }
}

private struct ConfidenceBadge: View {
    let value: String
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
    private var label: String {
        switch value {
        case "confirmed": "Confirmed"
        case "probable": "Probable"
        case "interpretation": "Interpretation"
        default: "Not specified"
        }
    }
    private var color: Color {
        switch value {
        case "confirmed": .green
        case "probable": .orange
        case "interpretation": .purple
        default: .secondary
        }
    }
}

private struct AddCharacterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add name and find mentions")
                .font(.title2.bold())
            Text("Enter the first or last name exactly as it appears in the book. Search runs locally on the extracted PDF text.")
                .foregroundStyle(.secondary)
            TextField("For example: Elizabeth Bennet", text: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Search") {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct TraitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = "Appearance"
    @State private var value = ""
    @State private var confidence = "confirmed"
    let evidence: [EvidenceRecord]
    let onSave: (String, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirmed trait").font(.title2.bold())
            TextField("Category", text: $category)
            TextField("Value", text: $value, axis: .vertical)
            Picker("Confidence", selection: $confidence) {
                Text("Confirmed").tag("confirmed")
                Text("Probable").tag("probable")
                Text("Not specified").tag("unspecified")
                Text("Interpretation").tag("interpretation")
            }
            Text("Linked to \(evidence.count) selected excerpts")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(evidence) { item in
                        Text(item.text)
                            .font(.caption)
                            .lineLimit(4)
                            .padding(9)
                            .bookLensCard()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(category, value, confidence)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || evidence.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 560)
    }
}

private struct MergeAliasesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: CharacterRecord
    let candidates: [CharacterRecord]
    let onMerge: (CharacterRecord) -> Void
    @State private var sourceID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Merge aliases").font(.title2.bold())
            Text("Choose the record that will become an alias of “\(target.name)”. Its evidence will be reassigned and the original record hidden.")
                .foregroundStyle(.secondary)
            Picker("Record", selection: $sourceID) {
                Text("Choose…").tag(UUID?.none)
                ForEach(candidates) { candidate in
                    Text(candidate.name).tag(Optional(candidate.id))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Merge") {
                    if let sourceID, let source = candidates.first(where: { $0.id == sourceID }) {
                        onMerge(source)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceID == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct ExtractedTextPreview: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [ChapterRecord]
    @State private var selectedChapterID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Extracted text")
                        .font(.title2.bold())
                    Text("Local preview — text is not sent to Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(18)
            Divider()

            HSplitView {
                List(selection: $selectedChapterID) {
                    ForEach(chapters) { chapter in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chapter.title)
                                .lineLimit(2)
                            Text("\(chapter.text.count.formatted()) characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(chapter.id)
                    }
                }
                .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)

                if let selectedChapter {
                    ScrollView {
                        Text(selectedChapter.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .frame(minWidth: 480)
                } else {
                    ContentUnavailableView("Choose a section", systemImage: "doc.text")
                        .frame(minWidth: 480)
                }
            }
        }
        .frame(width: 860, height: 640)
        .task {
            selectedChapterID = selectedChapterID ?? chapters.first?.id
        }
    }

    private var selectedChapter: ChapterRecord? {
        guard let selectedChapterID else { return nil }
        return chapters.first { $0.id == selectedChapterID }
    }
}
