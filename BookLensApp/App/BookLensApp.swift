import AppKit
import BookLensData
import BookLensSupport
import SwiftData
import SwiftUI

@main
struct BookLensApp: App {
    @NSApplicationDelegateAdaptor(BookLensAppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    private let modelContainer: ModelContainer = {
        do {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BookLensError.storageUnavailable
            }
            let directory = applicationSupport.appendingPathComponent("BookLens", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = Schema([
                BookRecord.self,
                ChapterRecord.self,
                CharacterRecord.self,
                TraitRecord.self,
                EvidenceRecord.self,
                GenerationJobRecord.self,
                ArtworkRecord.self,
            ])
            let configuration = ModelConfiguration(
                "BookLens",
                schema: schema,
                url: directory.appendingPathComponent("BookLens.store"),
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("BookLens SwiftData container failed: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView(model: appModel)
                .modelContainer(modelContainer)
                .tint(BookLensTheme.accent)
                .environment(\.locale, appModel.preferredLocale)
                .preferredColorScheme(appModel.preferredColorScheme)
                .frame(minWidth: 1_240, minHeight: 700)
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .windowIdealPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                BookLensAboutCommand()
            }

            CommandMenu(BookLensLocalization.string("Book")) {
                Button(BookLensLocalization.string("Add book…")) {
                    appModel.isFileImporterPresented = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(BookLensLocalization.string("Import from Apple Books…")) {
                    appModel.selectedSection = .library
                    appModel.selectedBookID = nil
                    appModel.isAppleBooksImportPresented = true
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                Button(BookLensLocalization.string("Close workspace")) {
                    appModel.selectedBookID = nil
                    appModel.selectedCharacterID = nil
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(appModel.selectedBookID == nil)
            }
        }

        WindowGroup(BookLensLocalization.string("Image viewer"), for: UUID.self) { $artworkID in
            if let artworkID {
                ArtworkViewerWindow(artworkID: artworkID)
                    .modelContainer(modelContainer)
                    .tint(BookLensTheme.accent)
                    .environment(\.locale, appModel.preferredLocale)
                    .preferredColorScheme(appModel.preferredColorScheme)
            }
        }
        .defaultSize(width: 1_100, height: 800)

        Window(BookLensLocalization.string("About BookLens"), id: "about") {
            AboutBookLensView()
                .tint(BookLensTheme.accent)
                .environment(\.locale, appModel.preferredLocale)
                .preferredColorScheme(appModel.preferredColorScheme)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: appModel)
                .modelContainer(modelContainer)
                .tint(BookLensTheme.accent)
                .environment(\.locale, appModel.preferredLocale)
                .preferredColorScheme(appModel.preferredColorScheme)
        }
    }
}

private struct BookLensAboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(BookLensLocalization.string("About BookLens")) {
            openWindow(id: "about")
        }
    }
}

final class BookLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
