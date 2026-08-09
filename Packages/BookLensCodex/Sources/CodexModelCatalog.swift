import BookLensSupport
import Foundation

public struct CodexReasoningOption: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { value }
    public let value: String
    public let description: String

    public init(value: String, description: String) {
        self.value = value
        self.description = description
    }
}

public struct CodexModelOption: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String
    public let isDefault: Bool
    public let defaultReasoningEffort: String
    public let supportedReasoningEfforts: [CodexReasoningOption]

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        isDefault: Bool,
        defaultReasoningEffort: String,
        supportedReasoningEfforts: [CodexReasoningOption]
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.isDefault = isDefault
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
    }

    public var familyName: String {
        if id.localizedCaseInsensitiveContains("luna") { return "Luna" }
        if id.localizedCaseInsensitiveContains("terra") { return "Terra" }
        if id.localizedCaseInsensitiveContains("sol") { return "Sol" }
        return displayName
    }
}

public struct CodexModelCatalogParser: Sendable {
    public init() {}

    public func parse(_ response: JSONValue) throws -> [CodexModelOption] {
        guard let values = response["data"]?.arrayValue else {
            throw BookLensError.protocolViolation(code: "model-list-shape")
        }
        return try values.map { value in
            guard let id = value["id"]?.stringValue,
                  let model = value["model"]?.stringValue,
                  let displayName = value["displayName"]?.stringValue,
                  let description = value["description"]?.stringValue,
                  let isDefault = value["isDefault"]?.boolValue,
                  let defaultEffort = value["defaultReasoningEffort"]?.stringValue,
                  let efforts = value["supportedReasoningEfforts"]?.arrayValue
            else {
                throw BookLensError.protocolViolation(code: "model-item-shape")
            }
            let reasoning = try efforts.map { option in
                guard let effort = option["reasoningEffort"]?.stringValue,
                      let description = option["description"]?.stringValue
                else {
                    throw BookLensError.protocolViolation(code: "model-effort-shape")
                }
                return CodexReasoningOption(value: effort, description: description)
            }
            return CodexModelOption(
                id: id,
                model: model,
                displayName: displayName,
                description: description,
                isDefault: isDefault,
                defaultReasoningEffort: defaultEffort,
                supportedReasoningEfforts: reasoning
            )
        }
    }
}
