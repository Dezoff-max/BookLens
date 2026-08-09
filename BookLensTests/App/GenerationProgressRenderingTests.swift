import AppKit
@testable import BookLens
import BookLensData
import BookLensDomain
import SwiftUI
import XCTest

@MainActor
final class GenerationProgressRenderingTests: XCTestCase {
    func testAIFeaturesRequireVersionedDisclosureAndExplicitEnablement() {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: "aiFeaturesEnabled")
        let previousVersion = defaults.object(forKey: "aiDisclosureVersion")
        defaults.removeObject(forKey: "aiFeaturesEnabled")
        defaults.removeObject(forKey: "aiDisclosureVersion")
        defer {
            if let previousEnabled { defaults.set(previousEnabled, forKey: "aiFeaturesEnabled") }
            else { defaults.removeObject(forKey: "aiFeaturesEnabled") }
            if let previousVersion { defaults.set(previousVersion, forKey: "aiDisclosureVersion") }
            else { defaults.removeObject(forKey: "aiDisclosureVersion") }
        }

        let model = AppModel()
        model.codexState = .available
        XCTAssertFalse(model.canUseAI)

        model.completeAIDisclosure(enableAI: false)
        XCTAssertFalse(model.canUseAI)

        model.setAIFeaturesEnabled(true)
        XCTAssertTrue(model.canUseAI)
    }

    func testEnglishLocalizationLoadsWithoutBundleModuleTrap() {
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: "languagePreference")
        defaults.set("en", forKey: "languagePreference")
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: "languagePreference")
            } else {
                defaults.removeObject(forKey: "languagePreference")
            }
        }

        XCTAssertEqual(BookLensLocalization.string("Home"), "Home")
        XCTAssertEqual(BookLensLocalization.string("Children"), "Children")
        XCTAssertEqual(BookLensLocalization.string("Use as book cover"), "Use as book cover")
        XCTAssertEqual(BookLensLocalization.string("Book classification"), "Book classification")
        XCTAssertEqual(BookLensLocalization.string("Save"), "Save")
        XCTAssertEqual(BookLensLocalization.string("Evidence from the book first — then an image."), "Evidence from the book first — then an image.")
        XCTAssertEqual(BookLensLocalization.string("Local import"), "Local import")
        XCTAssertEqual(BookLensLocalization.string("Readiness check"), "Readiness check")
        XCTAssertEqual(BookLensLocalization.string("Sign in with a code"), "Sign in with a code")
        XCTAssertEqual(BookLensLocalization.string("Bring book characters to life"), "Bring book characters to life")
        XCTAssertEqual(BookLensLocalization.string("Let's get started"), "Let's get started")
        XCTAssertEqual(BookLensLocalization.string("Your books stay on your Mac"), "Your books stay on your Mac")
        XCTAssertEqual(BookLensLocalization.string("Not checked"), "Not checked")
    }

    func testRussianLocalizationAndAnalysisOutputFollowPreference() {
        let defaults = UserDefaults.standard
        let previousPreference = defaults.object(forKey: "languagePreference")
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: "languagePreference")
            } else {
                defaults.removeObject(forKey: "languagePreference")
            }
            BookLensLocalization.languagePreferenceDidChange()
        }

        let model = AppModel()
        model.setLanguagePreference("ru")
        XCTAssertEqual(model.preferredLocale.identifier, "ru")
        XCTAssertEqual(BookLensLocalization.string("Home"), "Главная")
        XCTAssertEqual(BookLensLocalization.string("Book classification"), "Категория книги")
        XCTAssertEqual(BookLensLocalization.string("Save"), "Сохранить")
        XCTAssertEqual(model.analysisOutputLanguage, "Russian")

        model.setLanguagePreference("en")
        XCTAssertEqual(model.preferredLocale.identifier, "en")
        XCTAssertEqual(BookLensLocalization.string("Home"), "Home")
        XCTAssertEqual(model.analysisOutputLanguage, "English")
    }

    func testUnifiedBookCoverRendersEmbeddedAndSelectedGeneratedImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensCoverRendering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let embeddedURL = directory.appendingPathComponent("cover.png")
        let generatedURL = directory.appendingPathComponent("generated.png")
        try fixturePNG(color: .systemPurple).write(to: embeddedURL)
        try fixturePNG(color: .systemOrange).write(to: generatedURL)

        let book = BookRecord(
            title: "Fixture",
            author: "Author",
            sourceFilename: "fixture.epub",
            storedSourcePath: "/tmp/fixture.epub",
            coverPath: embeddedURL.path,
            coverSource: "epub"
        )
        let artwork = ArtworkRecord(
            jobID: UUID(),
            characterID: UUID(),
            bookID: book.id,
            filename: generatedURL.lastPathComponent,
            storedPath: generatedURL.path,
            sha256: "fixture",
            pixelWidth: 300,
            pixelHeight: 450,
            style: "cinematicRealism",
            composition: "bookWorld"
        )

        XCTAssertNotNil(renderCover(book: book, artwork: nil))
        book.coverArtworkID = artwork.id
        XCTAssertNotNil(renderCover(book: book, artwork: artwork))
    }

    func testDiagnosticsCreatesFirstLogFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("BookLens.log", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnostics = BookLensDiagnostics(logURL: logURL, forceEnabled: true)
        await diagnostics.record("test.started", fields: ["result": "success"])

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("INFO test.started result=success"))
    }

    func testDiagnosticsRedactsPrivateMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("BookLens.log", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnostics = BookLensDiagnostics(logURL: logURL, forceEnabled: true)
        await diagnostics.record("test.private", fields: [
            "email": "reader@example.com",
            "path": "/Users/reader/Library/Application Support/BookLens/private.txt",
        ])

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("reader@example.com"))
        XCTAssertFalse(contents.contains("/Users/reader"))
        XCTAssertTrue(contents.contains("REDACTED_EMAIL"))
        XCTAssertTrue(contents.contains("redacted-path"))
    }

    func testDiagnosticsAreDisabledWithoutOptIn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLensDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("BookLens.log", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "diagnosticsEnabled")
        defaults.removeObject(forKey: "diagnosticsEnabled")
        defer {
            if let previous {
                defaults.set(previous, forKey: "diagnosticsEnabled")
            } else {
                defaults.removeObject(forKey: "diagnosticsEnabled")
            }
        }

        let diagnostics = BookLensDiagnostics(logURL: logURL)
        await diagnostics.record("test.disabled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testEveryGenerationStateRendersWithoutStartingARequest() throws {
        let fixtures: [(GenerationState, String)] = [
            (.queued, "Checking Codex and account"),
            (.running, "Codex is creating the image"),
            (.saving, "Validating the image and SHA-256"),
            (.succeeded, "Image validated and saved"),
            (.failed, "Generation failed"),
        ]

        for (state, status) in fixtures {
            let renderer = ImageRenderer(
                content: AIGenerationProgressView(state: state, status: status)
                    .frame(width: 720, height: 680)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 720, height: 680)
            XCTAssertNotNil(renderer.cgImage, "State \(state.rawValue) did not render")

            if state == .running,
               let destination = ProcessInfo.processInfo.environment["BOOKLENS_PROGRESS_SNAPSHOT"],
               let image = renderer.cgImage
            {
                let representation = NSBitmapImageRep(cgImage: image)
                let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
            }
        }

        let reducedMotionRenderer = ImageRenderer(
            content: AIGenerationProgressView(
                state: .running,
                status: "Codex is creating the image",
                progress: 0.62,
                reduceMotionOverride: true
            )
            .frame(width: 720, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        )
        reducedMotionRenderer.scale = 2
        reducedMotionRenderer.proposedSize = ProposedViewSize(width: 720, height: 680)
        XCTAssertNotNil(reducedMotionRenderer.cgImage)

        let pageTurnRenderer = ImageRenderer(
            content: AIGenerationProgressView(
                state: .running,
                status: "Codex is creating the image",
                animationPhaseOverride: 0.86
            )
            .frame(width: 720, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        )
        pageTurnRenderer.scale = 2
        pageTurnRenderer.proposedSize = ProposedViewSize(width: 720, height: 680)
        let pageTurnImage = try XCTUnwrap(pageTurnRenderer.cgImage)

        if let destination = ProcessInfo.processInfo.environment["BOOKLENS_PAGE_TURN_SNAPSHOT"] {
            let representation = NSBitmapImageRep(cgImage: pageTurnImage)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
        }

        let lightRenderer = ImageRenderer(
            content: AIGenerationProgressView(
                state: .running,
                status: "Codex is creating the image",
                animationPhaseOverride: 0.52
            )
            .frame(width: 720, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        )
        lightRenderer.scale = 2
        lightRenderer.proposedSize = ProposedViewSize(width: 720, height: 680)
        let lightImage = try XCTUnwrap(lightRenderer.cgImage)

        if let destination = ProcessInfo.processInfo.environment["BOOKLENS_LIGHT_PROGRESS_SNAPSHOT"] {
            let representation = NSBitmapImageRep(cgImage: lightImage)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
        }

        let analysisRenderer = ImageRenderer(
            content: AIBookAnalysisProgressView(
                status: "AI is understanding the story and separating characters from incidental names…",
                animationPhaseOverride: 0.48,
                startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
                finishedAt: Date(timeIntervalSinceReferenceDate: 1_125)
            )
            .frame(width: 720, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        )
        analysisRenderer.scale = 2
        analysisRenderer.proposedSize = ProposedViewSize(width: 720, height: 680)
        let analysisImage = try XCTUnwrap(analysisRenderer.cgImage)

        if let destination = ProcessInfo.processInfo.environment["BOOKLENS_ANALYSIS_SNAPSHOT"] {
            let representation = NSBitmapImageRep(cgImage: analysisImage)
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
        }

        XCTAssertEqual(AIElapsedTimeView.formattedDuration(seconds: 65), "01:05")
        XCTAssertEqual(AIElapsedTimeView.formattedDuration(seconds: 3_661), "1:01:01")
        XCTAssertEqual(GenerationController.optimizedReasoningEffort("low"), "low")
        XCTAssertEqual(GenerationController.optimizedReasoningEffort("medium"), "medium")
        XCTAssertEqual(GenerationController.optimizedReasoningEffort("high"), "medium")
        XCTAssertEqual(GenerationController.optimizedReasoningEffort("ultra"), "medium")
    }

    private func renderCover(book: BookRecord, artwork: ArtworkRecord?) -> CGImage? {
        let renderer = ImageRenderer(
            content: BookCoverView(book: book, artwork: artwork)
                .frame(width: 240, height: 360)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 240, height: 360)
        return renderer.cgImage
    }

    private func fixturePNG(color: NSColor) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 450,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 450)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
