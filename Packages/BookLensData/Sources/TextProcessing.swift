import BookLensSupport
import Foundation
@preconcurrency import NaturalLanguage

public struct TextNormalizer: Sendable {
    public init() {}

    public func normalize(_ text: String) -> String {
        let canonical = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let lines = canonical.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ChapterSegmenter: Sendable {
    public init() {}

    public func segment(_ text: String) -> [ExtractedChapter] {
        let headingPattern = #"(?im)^(?:глава|chapter|часть|part)\s+(?:[ivxlcdm]+|\d+|[а-яёa-z]+).*?$"#
        guard let expression = try? NSRegularExpression(pattern: headingPattern) else {
            return [ExtractedChapter(title: "Text", text: text)]
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = expression.matches(in: text, range: fullRange)
        guard !matches.isEmpty else {
            return [ExtractedChapter(title: "Text", text: text)]
        }

        var chapters: [ExtractedChapter] = []
        for (index, match) in matches.enumerated() {
            guard let headingRange = Range(match.range, in: text) else { continue }
            let contentStart = headingRange.upperBound
            let contentEnd: String.Index
            if index + 1 < matches.count,
               let next = Range(matches[index + 1].range, in: text)
            {
                contentEnd = next.lowerBound
            } else {
                contentEnd = text.endIndex
            }
            let title = String(text[headingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(text[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                chapters.append(ExtractedChapter(title: title, text: body))
            }
        }
        return chapters.isEmpty ? [ExtractedChapter(title: "Text", text: text)] : chapters
    }
}

public struct NameCandidateFinder: Sendable {
    private let maximumCandidates: Int
    private let maximumEvidencePerCandidate: Int

    public init(maximumCandidates: Int = 80, maximumEvidencePerCandidate: Int = 5) {
        self.maximumCandidates = maximumCandidates
        self.maximumEvidencePerCandidate = maximumEvidencePerCandidate
    }

    public func find(in chapters: [ExtractedChapter]) -> [NameCandidate] {
        var names: [String: (display: String, count: Int, evidence: [CandidateEvidence])] = [:]
        for (chapterIndex, chapter) in chapters.enumerated() {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = chapter.text
            let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
            let range = chapter.text.startIndex..<chapter.text.endIndex
            tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
                guard tag == .personalName else { return true }
                let raw = String(chapter.text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard raw.count >= 2, raw.count <= 80 else { return true }
                let key = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                var entry = names[key] ?? (raw, 0, [])
                entry.count += 1
                if entry.evidence.count < maximumEvidencePerCandidate {
                    let excerpt = context(in: chapter.text, around: tokenRange)
                    let start = chapter.text.distance(from: chapter.text.startIndex, to: tokenRange.lowerBound)
                    let end = chapter.text.distance(from: chapter.text.startIndex, to: tokenRange.upperBound)
                    entry.evidence.append(
                        CandidateEvidence(
                            chapterIndex: chapterIndex,
                            excerpt: excerpt,
                            localRange: start..<end
                        )
                    )
                }
                names[key] = entry
                return true
            }
        }
        return names.values
            .filter { $0.count >= 2 }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.display < rhs.display : lhs.count > rhs.count
            }
            .prefix(maximumCandidates)
            .map { NameCandidate(name: $0.display, occurrenceCount: $0.count, evidence: $0.evidence) }
    }

    private func context(in text: String, around range: Range<String.Index>) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -180, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
