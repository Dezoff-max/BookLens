import AppKit
import BookLensCodex
import BookLensData
import BookLensDomain
import BookLensSupport
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let currentAIDisclosureVersion = 1

    enum CodexState: Equatable {
        case notChecked
        case checking
        case available
        case loginRequired
        case incompatible
        case unavailable
        case failed(code: String)

        var title: String {
            switch self {
            case .notChecked: BookLensLocalization.string("Not checked")
            case .checking: BookLensLocalization.string("Checking Codex…")
            case .available: BookLensLocalization.string("ChatGPT connected")
            case .loginRequired: BookLensLocalization.string("Sign-in required")
            case .incompatible: BookLensLocalization.string("Incompatible version")
            case .unavailable: BookLensLocalization.string("Codex not found")
            case let .failed(code): "\(BookLensLocalization.string("Error")) · \(code)"
            }
        }
    }

    var selectedSection: AppSection = .library
    var selectedBookID: UUID?
    var selectedCharacterID: UUID?
    var isFileImporterPresented = false
    var isAppleBooksImportPresented = false
    var isBookDiscoveryPresented = false
    var discoveryQuery = ""
    var codexState: CodexState = .notChecked
    var codexInstallation: CodexInstallation?
    var accountSnapshot: CodexAccountSnapshot?
    var modelOptions: [CodexModelOption] = AppModel.pinnedModelFallback
    var selectedModelID: String
    var selectedReasoningEffort: String
    var modelCatalogIsLive = false
    var loginChallenge: CodexLoginChallenge?
    var lastError: BookLensError?
    var selectedCreationMode: CharacterCreationMode = .portrait
    var languagePreference: String
    var appearancePreference: String
    var aiFeaturesEnabled: Bool
    var aiDisclosureVersion: Int

    let storage: FileStorage?
    let importPipeline: BookImportPipeline?

    private var loginSession: CodexAppServerSession?

    init() {
        selectedModelID = UserDefaults.standard.string(forKey: "selectedCodexModelID") ?? "gpt-5.6-sol"
        selectedReasoningEffort = UserDefaults.standard.string(forKey: "selectedCodexReasoningEffort") ?? "low"
        languagePreference = "en"
        appearancePreference = UserDefaults.standard.string(forKey: "appearancePreference") ?? "system"
        aiFeaturesEnabled = UserDefaults.standard.bool(forKey: "aiFeaturesEnabled")
        aiDisclosureVersion = UserDefaults.standard.integer(forKey: "aiDisclosureVersion")
        do {
            let storage = try FileStorage()
            self.storage = storage
            importPipeline = BookImportPipeline(storage: storage)
        } catch {
            storage = nil
            importPipeline = nil
            lastError = .storageUnavailable
        }
    }

    var preferredLocale: Locale {
        BookLensLocalization.locale(for: languagePreference)
    }

    var analysisOutputLanguage: String {
        "English"
    }

    var preferredColorScheme: ColorScheme? {
        switch appearancePreference {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var canUseAI: Bool {
        aiFeaturesEnabled
            && aiDisclosureVersion >= Self.currentAIDisclosureVersion
            && codexState == .available
    }

    var bookLensAIStatusTitle: String {
        if codexState == .available, !aiFeaturesEnabled {
            return BookLensLocalization.string("AI is disabled in BookLens")
        }
        return codexState.title
    }

    func completeAIDisclosure(enableAI: Bool) {
        aiDisclosureVersion = Self.currentAIDisclosureVersion
        aiFeaturesEnabled = enableAI
        UserDefaults.standard.set(aiDisclosureVersion, forKey: "aiDisclosureVersion")
        UserDefaults.standard.set(enableAI, forKey: "aiFeaturesEnabled")
    }

    func setAIFeaturesEnabled(_ enabled: Bool) {
        aiFeaturesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "aiFeaturesEnabled")
    }

    func setLanguagePreference(_ value: String) {
        let normalizedValue = BookLensLocalization.normalizedPreference(value)
        UserDefaults.standard.set(normalizedValue, forKey: "languagePreference")
        languagePreference = normalizedValue
        BookLensLocalization.languagePreferenceDidChange()
    }

    func setAppearancePreference(_ value: String) {
        appearancePreference = value
        UserDefaults.standard.set(value, forKey: "appearancePreference")
    }

    func refreshCodex() async {
        codexState = .checking
        lastError = nil
        do {
            let installation = try await CodexExecutableResolver().resolve()
            codexInstallation = installation
            guard installation.compatibility == .compatible else {
                codexState = .incompatible
                return
            }
            let session = CodexAppServerSession(installation: installation)
            _ = try await session.start()
            let account = try await session.readAccount()
            do {
                let catalog = try await session.listModels()
                applyModelCatalog(catalog, isLive: true)
            } catch {
                applyModelCatalog(Self.pinnedModelFallback, isLive: false)
            }
            await session.stop()
            accountSnapshot = account
            codexState = account.accountType == "chatgpt" ? .available : .loginRequired
        } catch let error as BookLensError {
            lastError = error
            codexState = error == .codexNotFound ? .unavailable : .failed(code: error.diagnosticCode)
        } catch {
            codexState = .failed(code: "BLX-CODEX-UNEXPECTED")
        }
    }

    var selectedModel: CodexModelOption? {
        modelOptions.first { $0.id == selectedModelID }
    }

    var reasoningOptions: [CodexReasoningOption] {
        selectedModel?.supportedReasoningEfforts ?? []
    }

    func selectModel(_ modelID: String) {
        guard let option = modelOptions.first(where: { $0.id == modelID }) else { return }
        selectedModelID = option.id
        if !option.supportedReasoningEfforts.contains(where: { $0.value == selectedReasoningEffort }) {
            selectedReasoningEffort = option.defaultReasoningEffort
        }
        persistModelSelection()
    }

    func selectReasoningEffort(_ value: String) {
        guard reasoningOptions.contains(where: { $0.value == value }) else { return }
        selectedReasoningEffort = value
        persistModelSelection()
    }

    func beginBrowserLogin() async {
        await beginLogin(deviceCode: false)
    }

    func beginDeviceCodeLogin() async {
        await beginLogin(deviceCode: true)
    }

    func cancelLogin() async {
        await loginSession?.stop()
        loginSession = nil
        loginChallenge = nil
    }

    func logout() async {
        do {
            let installation: CodexInstallation
            if let codexInstallation {
                installation = codexInstallation
            } else {
                installation = try await CodexExecutableResolver().resolve()
            }
            let session = CodexAppServerSession(installation: installation)
            _ = try await session.start()
            _ = try await session.request(method: "account/logout")
            await session.stop()
            accountSnapshot = nil
            codexState = .loginRequired
        } catch let error as BookLensError {
            lastError = error
            codexState = .failed(code: error.diagnosticCode)
        } catch {
            codexState = .failed(code: "BLX-AUTH-LOGOUT")
        }
    }

    private func beginLogin(deviceCode: Bool) async {
        do {
            let installation: CodexInstallation
            if let codexInstallation {
                installation = codexInstallation
            } else {
                installation = try await CodexExecutableResolver().resolve()
            }
            let session = CodexAppServerSession(installation: installation)
            _ = try await session.start()
            let challenge = deviceCode
                ? try await session.beginDeviceCodeLogin()
                : try await session.beginBrowserLogin()
            loginSession = session
            loginChallenge = challenge
            switch challenge.kind {
            case let .browser(url), let .deviceCode(url, _):
                NSWorkspace.shared.open(url)
            }
            observeLoginCompletion(session: session, loginID: challenge.loginID)
        } catch let error as BookLensError {
            lastError = error
            codexState = .failed(code: error.diagnosticCode)
        } catch {
            codexState = .failed(code: "BLX-AUTH-UNEXPECTED")
        }
    }

    private func observeLoginCompletion(session: CodexAppServerSession, loginID: String) {
        Task {
            for await notification in session.notifications() {
                guard notification.method == "account/login/completed",
                      notification.params?["loginId"]?.stringValue == loginID
                else { continue }
                await session.stop()
                loginSession = nil
                loginChallenge = nil
                await refreshCodex()
                return
            }
        }
    }

    private func applyModelCatalog(_ catalog: [CodexModelOption], isLive: Bool) {
        let order = ["luna": 0, "terra": 1, "sol": 2]
        let selected = catalog.filter { option in
            let id = option.id.lowercased()
            return id.contains("luna") || id.contains("terra") || id.contains("sol")
        }.sorted { lhs, rhs in
            func rank(_ option: CodexModelOption) -> Int {
                order.first(where: { option.id.lowercased().contains($0.key) })?.value ?? 99
            }
            return rank(lhs) < rank(rhs)
        }
        guard !selected.isEmpty else { return }
        modelOptions = selected
        modelCatalogIsLive = isLive
        if !selected.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = selected.first(where: \.isDefault)?.id ?? selected[0].id
        }
        if let model = selectedModel,
           !model.supportedReasoningEfforts.contains(where: { $0.value == selectedReasoningEffort })
        {
            selectedReasoningEffort = model.defaultReasoningEffort
        }
        persistModelSelection()
    }

    private func persistModelSelection() {
        UserDefaults.standard.set(selectedModelID, forKey: "selectedCodexModelID")
        UserDefaults.standard.set(selectedReasoningEffort, forKey: "selectedCodexReasoningEffort")
    }

    private static let pinnedModelFallback: [CodexModelOption] = {
        func efforts(_ values: [String]) -> [CodexReasoningOption] {
            values.map { value in
                CodexReasoningOption(value: value, description: value)
            }
        }
        return [
            CodexModelOption(
                id: "gpt-5.6-luna",
                model: "gpt-5.6-luna",
                displayName: "GPT-5.6-Luna",
                description: "Luna",
                isDefault: false,
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: efforts(["low", "medium", "high", "xhigh", "max"])
            ),
            CodexModelOption(
                id: "gpt-5.6-terra",
                model: "gpt-5.6-terra",
                displayName: "GPT-5.6-Terra",
                description: "Terra",
                isDefault: false,
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: efforts(["low", "medium", "high", "xhigh", "max", "ultra"])
            ),
            CodexModelOption(
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                displayName: "GPT-5.6-Sol",
                description: "Sol",
                isDefault: true,
                defaultReasoningEffort: "low",
                supportedReasoningEfforts: efforts(["low", "medium", "high", "xhigh", "max", "ultra"])
            ),
        ]
    }()
}
