import BookLensData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("aiDisclosureVersion") private var aiDisclosureVersion = 0
    @Query(sort: \BookRecord.importedAt, order: .reverse) private var books: [BookRecord]

    var body: some View {
        Group {
            if hasCompletedOnboarding,
               aiDisclosureVersion >= AppModel.currentAIDisclosureVersion {
                mainInterface
            } else {
                OnboardingView(model: model) { enableAI in
                    model.completeAIDisclosure(enableAI: enableAI)
                    aiDisclosureVersion = AppModel.currentAIDisclosureVersion
                    hasCompletedOnboarding = true
                }
            }
        }
        .task {
            await repairTransferredPaths()
            await repairMissingBookCovers()
            if model.aiFeaturesEnabled {
                await model.refreshCodex()
            }
        }
    }

    @MainActor
    private func repairTransferredPaths() async {
        guard let storage = model.storage else { return }
        let storageRoot = await storage.rootURL
        do {
            let summary = try PortablePathReconciler.reconcile(
                in: modelContext,
                storageRoot: storageRoot
            )
            guard summary.total > 0 else { return }
            await BookLensDiagnostics.shared.record(
                "storage.paths-repaired",
                fields: [
                    "artworks": String(summary.artworks),
                    "books": String(summary.bookSources),
                    "covers": String(summary.bookCovers),
                    "jobs": String(summary.jobDirectories),
                ]
            )
        } catch {
            await BookLensDiagnostics.shared.record(
                "storage.path-repair-failed",
                level: .error,
                fields: ["error": String(describing: error)]
            )
        }
    }

    @MainActor
    private func repairMissingBookCovers() async {
        guard let storage = model.storage else { return }
        let extractor = BookCoverExtractor()
        var repaired = 0
        for book in books where book.sourceKind == "local" {
            if !book.coverPath.isEmpty, FileManager.default.fileExists(atPath: book.coverPath) {
                continue
            }
            guard !book.storedSourcePath.isEmpty,
                  FileManager.default.fileExists(atPath: book.storedSourcePath),
                  let cover = try? await extractor.extractCover(
                      from: URL(fileURLWithPath: book.storedSourcePath)
                  ),
                  let stored = try? await storage.storeBookCover(
                      data: cover.data,
                      fileExtension: cover.fileExtension,
                      bookID: book.id
                  )
            else { continue }
            book.coverPath = stored.path
            book.coverSource = cover.source
            repaired += 1
        }
        guard repaired > 0 else { return }
        try? modelContext.save()
        await BookLensDiagnostics.shared.record(
            "storage.book-covers-repaired",
            fields: ["covers": String(repaired)]
        )
    }

    private var mainInterface: some View {
        NavigationSplitView {
            SidebarView(model: model, books: books)
                .frame(minWidth: 240, idealWidth: 240, maxWidth: 240)
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
                .layoutPriority(2)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button("Choose EPUB, TXT, or PDF…") {
                                model.isFileImporterPresented = true
                            }
                            Button("Import from Apple Books…") {
                                model.selectedSection = .library
                                model.selectedBookID = nil
                                model.isAppleBooksImportPresented = true
                            }
                            Button("Find a book by title…") {
                                model.selectedSection = .library
                                model.selectedBookID = nil
                                model.discoveryQuery = ""
                                model.isBookDiscoveryPresented = true
                            }
                        } label: {
                            Label("Add book", systemImage: "plus")
                        }
                        .help("Add EPUB, TXT, or PDF (⌘O)")

                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.selectedSection) { _, section in
            if section == .books {
                model.selectedBookID = nil
                model.selectedCharacterID = nil
            }
        }
        .fileImporter(
            isPresented: $model.isFileImporterPresented,
            allowedContentTypes: [
                .plainText,
                .pdf,
                UTType(importedAs: "org.idpf.epub-container"),
            ],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.selectedSection = .library
                NotificationCenter.default.post(name: .bookLensBeginImport, object: url)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .library:
            if let selectedBookID = model.selectedBookID,
               let book = books.first(where: { $0.id == selectedBookID })
            {
                BookExperienceView(model: model, book: book)
            } else {
                LibraryView(model: model)
            }
        case .books:
            if let selectedBookID = model.selectedBookID,
               let book = books.first(where: { $0.id == selectedBookID && $0.sourceKind == "local" })
            {
                BookReaderView(model: model, book: book)
            } else {
                MyBooksView(model: model)
            }
        case .characters:
            CharactersView(model: model)
        case .studio:
            StudioView(model: model)
        case .gallery:
            GalleryView(model: model)
        }
    }
}

extension Notification.Name {
    static let bookLensBeginImport = Notification.Name("BookLensBeginImport")
}
