import AppKit
import Foundation
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    let completion: (Bool) -> Void

    @State private var privacyDetailsAreExpanded = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                heroPane
                    .frame(width: max(660, geometry.size.width * 0.54))

                connectionPane(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(BookLensTheme.onboardingAccent)
        .task {
            if model.codexState == .notChecked {
                await model.refreshCodex()
            }
        }
    }

    private var heroPane: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(0.70),
                    .black.opacity(0.05),
                    .black.opacity(0.76),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                brand

                VStack(alignment: .leading, spacing: 12) {
                    Text("Bring book characters to life")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("BookLens extracts character facts from your books and turns them into vivid portraits grounded in quotes and context.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineSpacing(3)
                        .frame(maxWidth: 540, alignment: .leading)
                }
                .padding(.top, 34)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 22) {
                    OnboardingHeroFeature(
                        icon: "book.closed.fill",
                        title: "Import books locally",
                        detail: "EPUB, TXT, and PDF — everything stays on your Mac."
                    )
                    OnboardingHeroFeature(
                        icon: "quote.opening",
                        title: "Evidence-backed character profiles",
                        detail: "Traits, relationships, and key quotes."
                    )
                    OnboardingHeroFeature(
                        icon: "shield.lefthalf.filled",
                        title: "Your control, your choice",
                        detail: "ChatGPT through your installed Codex — only with your consent."
                    )
                }
            }
            .padding(46)
            .foregroundStyle(.white)
        }
        .background {
            heroArtwork
        }
        .clipped()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let imageURL = Bundle.module.url(forResource: "OnboardingHero-v1", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            Color.black
        }
    }

    private var brand: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BookLensTheme.onboardingAccent)
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)

            Text("BookLens")
                .font(.system(size: 36, weight: .bold, design: .rounded))
        }
    }

    private func connectionPane(minHeight: CGFloat) -> some View {
        let topPadding = min(max(72, minHeight * 0.13), 160)

        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let's get started")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Choose how BookLens will analyze your books.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                codexStatusCard

                VStack(spacing: 14) {
                    primaryAccountAction

                    OnboardingChoiceButton(
                        icon: "laptopcomputer",
                        title: "Continue without AI",
                        subtitle: "Local mode on this Mac",
                        prominent: false
                    ) {
                        completion(false)
                    }
                }

                if model.codexState == .loginRequired {
                    loginActions
                }

                if let error = model.lastError {
                    Text(verbatim: "\(error.localizedDescription) · \(error.diagnosticCode)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                if case let .deviceCode(_, code) = model.loginChallenge?.kind {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Sign-in code")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(.title2, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .bookLensCard()
                }

                privacyNotice
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 52)
            .padding(.top, topPadding)
            .padding(.bottom, 52)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .background(.regularMaterial)
    }

    private var codexStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                statusIndicator

                VStack(alignment: .leading, spacing: 3) {
                    Text("ChatGPT (Codex)")
                        .font(.system(size: 18, weight: .semibold))
                    Text(verbatim: model.codexState.title)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(model.codexInstallation == nil ? "Check" : "Check again") {
                    Task { await model.refreshCodex() }
                }
                .disabled(model.codexState == .checking)
            }

            if let installation = model.codexInstallation {
                Text(verbatim: "Codex \(installation.version) · \(installation.architecture) · \(installation.signingTeamIdentifier)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("This checks only the installed Codex and current account type. No books or excerpts are sent at this step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.codexState == .available {
                Label("An active ChatGPT session was found in Codex", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            limitSummary

            if model.codexState == .available {
                Label(
                    "Uses your ChatGPT subscription and plan limits — no API key or separate OpenAI API billing.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if model.codexState == .unavailable {
                Link("How to install Codex", destination: URL(string: "https://learn.chatgpt.com/docs/codex/cli")!)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch model.codexState {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .notChecked:
            Image(systemName: "circle.dotted")
                .font(.title2)
                .foregroundStyle(BookLensTheme.onboardingAccent)
        case .loginRequired:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
        case .incompatible, .unavailable, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var limitSummary: some View {
        if let account = model.accountSnapshot,
           let rateLimit = account.primaryRateLimit {
            Divider()
            CodexLimitView(
                rateLimit: rateLimit,
                isStale: !account.hasRateLimitSnapshot
            )
        } else if model.codexState == .checking {
            Label("Refreshing limit…", systemImage: "gauge.with.dots.needle.0percent")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.codexState == .available {
            Label("Limit temporarily unavailable", systemImage: "gauge.with.dots.needle.0percent")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var primaryAccountAction: some View {
        switch model.codexState {
        case .available:
            OnboardingChoiceButton(
                icon: "sparkles",
                title: "Use this ChatGPT account",
                subtitle: "Use Codex for book analysis and image creation",
                prominent: true
            ) {
                completion(true)
            }
        case .loginRequired:
            OnboardingChoiceButton(
                icon: "person.crop.circle.badge.plus",
                title: "Sign in with ChatGPT",
                subtitle: "A regular ChatGPT account — no API key",
                prominent: true
            ) {
                Task { await model.beginBrowserLogin() }
            }
        default:
            OnboardingChoiceButton(
                icon: "sparkles",
                title: "Check Codex and account",
                subtitle: "Use ChatGPT only after you choose",
                prominent: true,
                isDisabled: model.codexState == .checking
            ) {
                Task { await model.refreshCodex() }
            }
        }
    }

    private var loginActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let accountType = model.accountSnapshot?.accountType,
               accountType != "chatgpt" {
                Text(verbatim: String(
                    format: BookLensLocalization.string("Detected %@ mode. BookLens supports only a regular ChatGPT account login; an API key will not be used."),
                    accountType
                ))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Sign in with a code") {
                Task { await model.beginDeviceCodeLogin() }
            }
        }
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your books stay on your Mac")
                        .font(.system(size: 18, weight: .semibold))
                    Text("BookLens starts locally. Book files are not sent; data goes to ChatGPT/Codex only after separate confirmation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup("Privacy details", isExpanded: $privacyDetailsAreExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Only after you confirm, BookLens sends the title, author, structure, and selected book excerpts — no more than 96,000 characters per analysis. Image generation sends selected quotes, the character description, and scene settings.")
                    Text("BookLens does not read or store your password, tokens, auth.json, or an API key. Requests use your ChatGPT plan limits. Signing in or out changes the shared Codex session on this Mac.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.top, 4)
    }
}

private struct OnboardingHeroFeature: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.28), in: Circle())
                .overlay {
                    Circle().strokeBorder(BookLensTheme.onboardingAccent.opacity(0.95), lineWidth: 1.2)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }
}

private struct OnboardingChoiceButton: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let prominent: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 21, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 16))
                        .opacity(0.78)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 104)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(prominent ? AnyShapeStyle(BookLensTheme.onboardingAccent) : AnyShapeStyle(.thinMaterial))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: prominent ? BookLensTheme.onboardingAccent.opacity(0.20) : .clear, radius: 12, y: 5)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}
