import BookLensDomain
import Foundation

public struct CodexRateLimitParser: Sendable {
    public init() {}

    public func parsePrimary(from response: JSONValue) -> CodexRateLimitSnapshot? {
        let buckets = response["rateLimitsByLimitId"]?.objectValue
        let keyedCodexBucket = buckets?["codex"]?.objectValue.map(JSONValue.object)
        let identifiedCodexBucket = buckets?.values.first(where: {
            $0["limitId"]?.stringValue == "codex"
        })
        let fallbackBucket = response["rateLimits"]

        for root in [keyedCodexBucket, identifiedCodexBucket, fallbackBucket].compactMap({ $0 }) {
            guard let primary = root["primary"],
                  let usedPercent = primary["usedPercent"]?.intValue
            else {
                continue
            }

            let resetDate = primary["resetsAt"]?.intValue.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            return CodexRateLimitSnapshot(
                limitID: root["limitId"]?.stringValue,
                limitName: root["limitName"]?.stringValue,
                usedPercent: usedPercent,
                windowDurationMinutes: primary["windowDurationMins"]?.intValue,
                resetsAt: resetDate
            )
        }
        return nil
    }
}
