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

}

public struct CodexModelCatalogParser: Sendable {
    public init() {}

    public func parse(_ response: JSONValue) throws -> [CodexModelOption] {
        guard let values = response["data"]?.arrayValue else {
            throw BookLensError.protocolViolation(code: "model-list-shape")
        }
        return try values.filter { $0["hidden"]?.boolValue != true }.map { value in
            guard let id = value["id"]?.stringValue,
                  let model = value["model"]?.stringValue,
                  let displayName = value["displayName"]?.stringValue,
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
                description: value["description"]?.stringValue ?? "",
                isDefault: isDefault,
                defaultReasoningEffort: defaultEffort,
                supportedReasoningEfforts: reasoning
            )
        }
    }
}

/// Loads all picker-visible models without assuming names, generations, or page size.
public struct CodexModelCatalog: Sendable {
    public init() {}

    public func load(using client: JSONRPCClient) async throws -> [CodexModelOption] {
        var models: [CodexModelOption] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        for _ in 0..<20 {
            var params: [String: JSONValue] = ["includeHidden": false, "limit": 100]
            if let cursor { params["cursor"] = .string(cursor) }
            let response = try await client.request(method: "model/list", params: .object(params))
            models += try CodexModelCatalogParser().parse(response).filter { seenIDs.insert($0.id).inserted }
            guard let next = response["nextCursor"]?.stringValue, !next.isEmpty else {
                guard !models.isEmpty else {
                    throw BookLensError.protocolViolation(code: "model-list-empty")
                }
                return models
            }
            guard seenCursors.insert(next).inserted else {
                throw BookLensError.protocolViolation(code: "model-list-cursor")
            }
            cursor = next
        }
        throw BookLensError.protocolViolation(code: "model-list-page-limit")
    }
}
