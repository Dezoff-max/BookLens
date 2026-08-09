import Foundation

public enum BookAudience: String, CaseIterable, Codable, Identifiable, Sendable {
    case unspecified
    case children
    case teen
    case adult

    public var id: String { rawValue }

    public init(storedValue: String) {
        self = Self(rawValue: storedValue) ?? .unspecified
    }
}

public enum BookClassificationConfidence: String, CaseIterable, Codable, Sendable {
    case unspecified
    case low
    case medium
    case high
    case manual
}
