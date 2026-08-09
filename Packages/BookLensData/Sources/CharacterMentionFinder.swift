import Foundation

public struct CharacterMentionFinder: Sendable {
    private let maximumEvidence: Int

    public init(maximumEvidence: Int = 40) {
        self.maximumEvidence = maximumEvidence
    }

    public func find(
        name: String,
        aliases: [String] = [],
        in chapters: [ExtractedChapter]
    ) -> NameCandidate {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = ([displayName] + aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        var occurrenceCount = 0
        var evidence: [CandidateEvidence] = []

        for (chapterIndex, chapter) in chapters.enumerated() {
            var acceptedRanges: [Range<Int>] = []
            for term in terms {
                guard let expression = expression(for: term) else { continue }
                let fullRange = NSRange(chapter.text.startIndex..., in: chapter.text)
                for match in expression.matches(in: chapter.text, range: fullRange) {
                    guard let stringRange = Range(match.range, in: chapter.text) else { continue }
                    let lower = chapter.text.distance(from: chapter.text.startIndex, to: stringRange.lowerBound)
                    let upper = chapter.text.distance(from: chapter.text.startIndex, to: stringRange.upperBound)
                    let localRange = lower..<upper
                    guard !acceptedRanges.contains(where: { $0.overlaps(localRange) }) else { continue }

                    acceptedRanges.append(localRange)
                    occurrenceCount += 1
                    if evidence.count < maximumEvidence {
                        evidence.append(
                            CandidateEvidence(
                                chapterIndex: chapterIndex,
                                excerpt: context(in: chapter.text, around: stringRange),
                                localRange: localRange
                            )
                        )
                    }
                }
            }
        }

        return NameCandidate(
            name: displayName,
            occurrenceCount: occurrenceCount,
            evidence: evidence
        )
    }

    private func expression(for term: String) -> NSRegularExpression? {
        let escapedWords = term
            .split(whereSeparator: { $0.isWhitespace })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !escapedWords.isEmpty else { return nil }
        let flexibleName = escapedWords.joined(separator: #"\s+"#)
        let pattern = #"(?<![\p{L}\p{N}_-])"# + flexibleName + #"(?![\p{L}\p{N}_-])"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private func context(in text: String, around range: Range<String.Index>) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -180, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
