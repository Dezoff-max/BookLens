@testable import BookLens
import BookLensCodex
import Foundation
import Testing

@MainActor
struct ModelSelectionTests {
    private func option(_ id: String, isDefault: Bool = false, efforts: [String] = ["low", "medium"]) -> CodexModelOption {
        CodexModelOption(id: id, model: id, displayName: id, description: "", isDefault: isDefault,
                         defaultReasoningEffort: "medium",
                         supportedReasoningEfforts: efforts.map { .init(value: $0, description: $0) })
    }

    @Test func retainsAllFamiliesAndUserSelectionAcrossRefreshAndRelaunch() throws {
        let suite = "BookLensModelSelection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        #expect(model.selectedModelID == "gpt-6.1-sol")
        let catalog = [option("gpt-6.1-sol", isDefault: true), option("gpt-6-astra"), option("future-model")]
        model.applyModelCatalog(catalog, isLive: true)
        #expect(model.modelOptions.map(\.id) == catalog.map(\.id))
        model.selectModel("gpt-6-astra")
        model.selectReasoningEffort("medium")
        model.applyModelCatalog(catalog, isLive: true)
        #expect(model.selectedModelID == "gpt-6-astra")
        #expect(model.selectedReasoningEffort == "medium")
        #expect(model.modelCatalogIsLive)
        let relaunched = AppModel(defaults: defaults)
        #expect(relaunched.selectedModelID == "gpt-6-astra")
        #expect(relaunched.selectedReasoningEffort == "medium")
    }

    @Test func retiredSelectionUsesServerDefaultAndRepairsUnsupportedEffort() throws {
        let suite = "BookLensModelSelection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("retired", forKey: "selectedCodexModelID")
        defaults.set("ultra", forKey: "selectedCodexReasoningEffort")
        let model = AppModel(defaults: defaults)
        model.applyModelCatalog([option("first"), option("recommended", isDefault: true)], isLive: true)
        #expect(model.selectedModelID == "recommended")
        #expect(model.selectedReasoningEffort == "medium")
        model.selectModel("not-in-catalog")
        model.selectReasoningEffort("unsupported")
        #expect(model.selectedModelID == "recommended")
        #expect(model.selectedReasoningEffort == "medium")
    }

    @Test func keepsAvailableLegacyModelInsteadOfForcingUpgrade() throws {
        let suite = "BookLensModelSelection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("gpt-5.6-luna", forKey: "selectedCodexModelID")
        let model = AppModel(defaults: defaults)
        model.applyModelCatalog([option("gpt-6.1-sol", isDefault: true), option("gpt-5.6-luna")], isLive: true)
        #expect(model.selectedModelID == "gpt-5.6-luna")
    }
}
