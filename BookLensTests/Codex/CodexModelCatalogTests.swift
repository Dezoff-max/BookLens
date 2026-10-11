@testable import BookLensCodex
import BookLensSupport
import Testing

struct CodexModelCatalogTests {
    private func item(_ id: String, hidden: Bool = false) -> JSONValue {
        [
            "id": .string(id), "model": .string(id), "displayName": .string(id),
            "hidden": .bool(hidden), "isDefault": false,
            "defaultReasoningEffort": "low",
            "supportedReasoningEfforts": [
                ["reasoningEffort": "low", "description": "Fast"],
                ["reasoningEffort": "ultra", "description": "Ultra"],
            ],
        ]
    }

    @Test func includesNewFamiliesAndFutureEffortsWithoutRequiringDescription() throws {
        let models = try CodexModelCatalogParser().parse([
            "data": .array([item("gpt-6.1-sol"), item("gpt-6-astra"), item("future-model")]),
        ])
        #expect(models.map(\.id) == ["gpt-6.1-sol", "gpt-6-astra", "future-model"])
        #expect(models.first?.description == "")
        #expect(models.last?.supportedReasoningEfforts.map(\.value) == ["low", "ultra"])
    }

    @Test func hiddenModelsAreExcluded() throws {
        let models = try CodexModelCatalogParser().parse([
            "data": .array([item("gpt-6-astra"), item("hidden", hidden: true)]),
        ])
        #expect(models.map(\.id) == ["gpt-6-astra"])
    }

    @Test func rejectsMalformedResponse() {
        #expect(throws: BookLensError.self) { try CodexModelCatalogParser().parse(["wrong": []]) }
        #expect(throws: BookLensError.self) { try CodexModelCatalogParser().parse(["data": [["id": "broken"]]]) }
    }

    @Test func followsPagesAndDeduplicatesInServerOrder() async throws {
        let transport = FixtureCodexTransport(responsesByMethod: ["model/list": [
            ["data": .array([item("gpt-6.1-sol")]), "nextCursor": "second"],
            ["data": .array([item("gpt-6.1-sol"), item("gpt-6-astra")]), "nextCursor": .null],
        ]])
        let client = JSONRPCClient(transport: transport, defaultTimeout: .seconds(1))
        try await client.start()
        do {
            let models = try await CodexModelCatalog().load(using: client)
            #expect(models.map(\.id) == ["gpt-6.1-sol", "gpt-6-astra"])
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }

    @Test func rejectsRepeatedCursorAndEmptyCatalog() async throws {
        for responses: [JSONValue] in [
            [["data": [], "nextCursor": .null]],
            [["data": .array([item("one")]), "nextCursor": "loop"],
             ["data": [], "nextCursor": "loop"]],
        ] {
            let transport = FixtureCodexTransport(responsesByMethod: ["model/list": responses])
            let client = JSONRPCClient(transport: transport, defaultTimeout: .seconds(1))
            try await client.start()
            await #expect(throws: BookLensError.self) { try await CodexModelCatalog().load(using: client) }
            await client.stop()
        }
    }
}
