import Foundation

public struct Redactor: Sendable {
    public init() {}

    public func redact(_ value: String) -> String {
        var result = value
        result = replacing(
            pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: result,
            with: "***REDACTED_EMAIL***"
        )
        result = replacing(
            pattern: #"(?i)(bearer\s+|api[_-]?key\s*[=:]\s*|token\s*[=:]\s*)[^\s,;\"]+"#,
            in: result,
            with: "$1***REDACTED***"
        )
        result = replacing(
            pattern: #"(?i)(/Users/|/Volumes/)[^\s\"]+"#,
            in: result,
            with: "<redacted-path>"
        )
        return result
    }

    public func metadata(
        requestID: String,
        method: String,
        durationMilliseconds: Int,
        resultCode: String,
        messageSize: Int,
        jobID: UUID?,
        protocolVersion: String
    ) -> [String: String] {
        [
            "request_id": requestID,
            "method": method,
            "duration_ms": String(durationMilliseconds),
            "result_code": resultCode,
            "message_size": String(messageSize),
            "job_id": jobID?.uuidString.lowercased() ?? "none",
            "protocol_version": protocolVersion,
        ]
    }

    private func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: replacement
        )
    }
}
