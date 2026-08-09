import AppKit
import BookLensData
import BookLensDomain
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("defaultStrictToBook") private var defaultStrictToBook = true
    @AppStorage("diagnosticsEnabled") private var diagnosticsEnabled = false
    @Query private var books: [BookRecord]
    @Query private var artworks: [ArtworkRecord]
    @State private var confirmsLogout = false

    var body: some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { model.appearancePreference },
                        set: { model.setAppearancePreference($0) }
                    )) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker("Language", selection: Binding(
                        get: { model.languagePreference },
                        set: { model.setLanguagePreference($0) }
                    )) {
                        Text("System").tag("system")
                        Text(verbatim: "Русский").tag("ru")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Español").tag("es")
                    }
                    .pickerStyle(.segmented)

                    Text("By default, BookLens uses the macOS language and appearance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }

            Form {
                Section("Codex") {
                    LabeledContent("Status") {
                        Text(verbatim: model.codexState.title)
                    }
                    if let installation = model.codexInstallation {
                        LabeledContent("Version", value: installation.version)
                        LabeledContent("Architecture", value: installation.architecture)
                        LabeledContent("Codex signature", value: installation.signingTeamIdentifier)
                        LabeledContent("Path") {
                            Text(installation.executableURL.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    if let account = model.accountSnapshot {
                        LabeledContent("Account type", value: account.accountType ?? "Unavailable")
                        LabeledContent("Plan", value: account.planType ?? "Unknown")
                        if let rateLimit = account.primaryRateLimit {
                            CodexLimitView(rateLimit: rateLimit)
                        } else {
                            LabeledContent("Limit", value: "temporarily unavailable")
                        }
                    }
                }
                Section("AI in BookLens") {
                    Toggle("Enable AI features after disclosure", isOn: Binding(
                        get: { model.aiFeaturesEnabled },
                        set: { model.setAIFeaturesEnabled($0) }
                    ))
                    Text("This disables AI only in BookLens and does not sign out of the shared Codex session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("BookLens uses your existing ChatGPT subscription and plan limits through Codex. No API key or separate OpenAI API billing is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Model and reasoning") {
                    Picker("Model", selection: Binding(
                        get: { model.selectedModelID },
                        set: { model.selectModel($0) }
                    )) {
                        ForEach(model.modelOptions) { option in
                            Text(option.familyName).tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Reasoning") {
                        Picker("Reasoning", selection: Binding(
                            get: { model.selectedReasoningEffort },
                            set: { model.selectReasoningEffort($0) }
                        )) {
                            ForEach(model.reasoningOptions) { option in
                                Text(reasoningLabel(option.value)).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Text(verbatim: "\(model.selectedModel?.displayName ?? model.selectedModelID) · \(BookLensLocalization.string(model.modelCatalogIsLive ? "Codex catalog" : "compatible values"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button("Check again") { Task { await model.refreshCodex() } }
                        if model.codexState == .loginRequired {
                            Button("Sign in with ChatGPT") { Task { await model.beginBrowserLogin() } }
                            Button("Sign in with a code") { Task { await model.beginDeviceCodeLogin() } }
                        }
                        Spacer()
                        if model.codexState == .available {
                            Button("Sign out…", role: .destructive) { confirmsLogout = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("ChatGPT and Codex", systemImage: "person.crop.circle.badge.checkmark") }

            Form {
                Section("Local library") {
                    LabeledContent("Books", value: String(books.count))
                    LabeledContent("Images", value: String(artworks.count))
                    LabeledContent("Storage") {
                        Text(applicationSupportPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text("Removing a book always requires confirmation. The original file outside BookLens is never changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Library", systemImage: "books.vertical") }

            Form {
                Section("Generation") {
                    Toggle("Follow the book by default", isOn: $defaultStrictToBook)
                    Text("A generation succeeds only after a new file is found, decoded by ImageIO, and verified with SHA-256.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Generation", systemImage: "paintbrush.pointed") }

            Form {
                Section("Privacy") {
                    Text("BookLens never reads tokens, cookies, auth.json, credentials, or .env. Authentication is managed by codex app-server.")
                    Text("Only after confirmation, BookLens sends the title, author, headings, and up to 96,000 characters of selected excerpts. The original file is neither sent nor modified.")
                    Text("Requests use your ChatGPT account and limits. API keys are not supported. Signing in or out changes the shared Codex session on this Mac.")
                    Text("For online search, only the user’s query is sent; the result and character list are returned in the selected app language.")
                    Text("Diagnostics never contain email, full book text, full prompts, binary images, or unredacted absolute paths.")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Privacy", systemImage: "hand.raised") }

            Form {
                Section("Diagnostics") {
                    Toggle("Save technical diagnostics only", isOn: $diagnosticsEnabled)
                    LabeledContent("Log file") {
                        Text(BookLensDiagnostics.logURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Button("Open Logs Folder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([BookLensDiagnostics.logURL])
                    }
                    Text("Only stages, duration, result codes, image dimensions, job UUID, and protocol metadata are logged. Book text, full prompts, images, and tokens are never logged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 760, height: 570)
        .scenePadding()
        .confirmationDialog("Sign out of ChatGPT in Codex?", isPresented: $confirmsLogout) {
            Button("Sign out", role: .destructive) { Task { await model.logout() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This changes the global Codex sign-in state on this Mac.")
        }
    }

    private var applicationSupportPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BookLens").path ?? "Unavailable"
    }

    private func reasoningLabel(_ value: String) -> String {
        switch value {
        case "low": "Fast (low)"
        case "medium": "Balanced (medium)"
        case "high": "Deep (high)"
        case "xhigh": "Very deep (xhigh)"
        case "max": "Maximum (max)"
        case "ultra": "Ultra"
        default: value
        }
    }
}
