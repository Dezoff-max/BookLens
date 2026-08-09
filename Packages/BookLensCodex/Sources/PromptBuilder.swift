import BookLensDomain
import BookLensSupport
import Foundation

public struct BookPromptContext: Hashable, Sendable {
    public let title: String
    public let author: String
    public let synopsis: String
    public let importantCharacters: [String]

    public init(
        title: String,
        author: String,
        synopsis: String,
        importantCharacters: [String]
    ) {
        self.title = title
        self.author = author
        self.synopsis = synopsis
        self.importantCharacters = importantCharacters
    }
}

public struct PromptBuilder: Sendable {
    public init() {}

    public func build(
        profile: CharacterProfileSnapshot,
        availableEvidenceIDs: Set<UUID>,
        evidenceByID: [UUID: String] = [:],
        bookContext: BookPromptContext? = nil,
        settings: GenerationSettings,
        references: [GenerationReference],
        outputDirectory: URL
    ) throws -> String {
        try CharacterProfileValidator().validate(
            traits: profile.traits,
            availableEvidenceIDs: availableEvidenceIDs
        )

        let traitLines = profile.traits.map { trait in
            let evidence = trait.evidenceIDs.map(\.uuidString).joined(separator: ", ")
            return "- \(trait.category): \(trait.value) [\(trait.confidence.rawValue); evidence: \(evidence.isEmpty ? "none" : evidence)]"
        }.joined(separator: "\n")

        let referenceLines = references.isEmpty
            ? "none"
            : references.map { reference in
                "- artwork \(reference.artworkID.uuidString.lowercased()); face=\(reference.preserveFace); clothing=\(reference.preserveClothing); composition=\(reference.preserveComposition)"
            }.joined(separator: "\n")

        let addition = settings.artisticAdditions.trimmingCharacters(in: .whitespacesAndNewlines)
        let additions = addition.isEmpty ? "none" : addition
        let evidenceLines = evidenceByID
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { id, text in
                let compact = text.replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return "- [\(id.uuidString.lowercased())] \(compact)"
            }
            .joined(separator: "\n")

        let bookContextLines: String
        if let bookContext {
            let synopsis = compact(bookContext.synopsis, limit: 1_600)
            let characters = bookContext.importantCharacters
                .prefix(6)
                .map { "- \(compact($0, limit: 420))" }
                .joined(separator: "\n")
            bookContextLines = """
            - work: \(compact(bookContext.title, limit: 240))
            - author: \(compact(bookContext.author, limit: 180))
            - short context: \(synopsis.isEmpty ? "not provided" : synopsis)
            - important characters:
            \(characters.isEmpty ? "- not provided" : characters)
            """
        } else {
            bookContextLines = "- not provided"
        }

        let compositionInstructions = instructions(for: settings.composition, anchor: profile.characterName)
        let objective = settings.composition == .bookWorld
            ? "Create one cohesive wide illustration of the literary world using the confirmed context."
            : "Create an image of the literary character using the confirmed profile."

        return """
        $imagegen

        \(objective)
        Do not use the likeness of actors from screen adaptations.
        Do not add text, logos, captions, or frames.
        Do not turn an unspecified trait into a fact.
        Always keep the selected character's entire head inside the frame and show the face clearly from the front or at a three-quarter angle.
        Never create a headless figure, crop the head, crown, face, or chin at the frame edge, or hide the face behind an object, deep shadow, or another character.
        If the book does not specify facial features, create a neutral natural appearance plausible for the stated age, era, origin, and role. Do not present neutral details as confirmed facts from the book.

        A credible book-world environment is required:
        - infer the era, country or region, social setting, season, and suitable time of day from the title, author, synopsis, profile, and quotes;
        - place the character in a readable interior or location from the book world, not against a flat, gradient, blurred beige/brown, or generic warm studio background;
        - show historically and narratively plausible architecture, wall finishes, windows, doors, flooring, furniture, textiles, and at least 3–5 distinct period or occupation-specific objects;
        - choose objects related to the character's role and book context, such as letters, books, maps, clocks, tableware, weapons, tools, documents, or transport, only when plausible for the book;
        - use light sources appropriate to the era, such as daylight, candles, a fireplace, oil or gas lamps, or period-correct electric lighting; do not apply the same warm orange grading to every book;
        - keep the background sharp and informative enough to communicate time, place, and world without competing with the character's face;
        - when the exact room or location is not named, choose a restrained historically plausible setting based on era, country, status, and occupation; do not replace uncertainty with an empty photo studio or claim neutral details are canon;
        - these environment rules override `background` and apply even to portraits and studio portrait style unless the user explicitly requests otherwise in artistic additions.

        Character: \(profile.characterName)
        Profile:
        \(traitLines.isEmpty ? "- no confirmed visual traits provided" : traitLines)

        Supporting excerpts:
        \(evidenceLines.isEmpty ? "- not provided" : evidenceLines)

        Book context:
        \(bookContextLines)

        Style and composition:
        - composition: \(settings.composition.rawValue)
        - style: \(settings.style.rawValue)
        - aspect ratio: \(settings.aspectRatio)
        - lighting: \(settings.lighting)
        - background: \(settings.background)
        - mood: \(settings.mood)
        - strict to book: \(settings.strictToBook)
        - explicit artistic additions: \(additions)

        Composition rules:
        \(compositionInstructions)

        Final file quality:
        - 2K HDR with maximum available detail and clean artifact-free texture;
        - target at least 2560 px on the long side and 1440 px on the short side when the selected aspect ratio permits;
        - use 2048 × 2560 px as the target for vertical 4:5 and 2560 × 1440 px for horizontal 16:9;
        - preserve highlight and shadow detail with natural contrast and no clipped highlights or crushed blacks;
        - save the full-size final result, not a thumbnail, preview, or reduced copy;
        - do not imitate detail through excessive sharpening, noise, halos, or artificial upscaling.

        References:
        \(referenceLines)

        Save exactly one final PNG or JPEG directly in this existing folder:
        \(outputDirectory.path)
        Do not save the final file anywhere else.
        """
    }

    private func instructions(for composition: PortraitComposition, anchor: String) -> String {
        switch composition {
        case .portrait:
            "- portrait with the entire head, crown, face, and chin visible; leave safe space above the head; the character fills about 55–70% of the frame, with a readable book-world interior or location and period objects behind them"
        case .waistUp:
            "- show the character waist-up; keep the head and face fully inside the frame and hands away from the face; leave enough space for a recognizable interior, furniture, and story-relevant objects"
        case .fullBody:
            "- show the character full-body from crown to feet; keep the figure and head entirely in frame; use flooring, architecture, furniture, and surrounding objects to create a deep historically credible scene"
        case .scene:
            "- show the character acting within a confirmed scene from the book; keep the head and face fully visible; use the interior or location, time of day, light, and objects to reveal the era and story instead of serving as a decorative warm background"
        case .bookWorld:
            """
            - create one cohesive cinematic image, not a collage, portrait set, or lineup;
            - \(anchor) is the main visual and narrative focus, while 2–4 other important characters from the supplied list appear in the scene;
            - keep every key character's head and face anatomically correct and entirely inside the frame; show \(anchor)'s face clearly;
            - devote a significant part of the frame to a recognizable key location, architecture, era, weather, and objects that reveal the work;
            - communicate relationships and conflict through position, action, and distance rather than simple posing;
            - use only elements supported by the synopsis, descriptions, and excerpts; when evidence is limited, choose neutral details without false specificity;
            - use a wide 16:9 composition with deep foreground, middle ground, and background and a visually readable story in one frame.
            """
        }
    }

    private func compact(_ value: String, limit: Int) -> String {
        let normalized = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(limit))
    }
}
