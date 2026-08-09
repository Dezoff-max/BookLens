import SwiftUI

struct CodexStatusBadge: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            Task { await model.refreshCodex() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ChatGPT")
                        .font(.caption.weight(.semibold))
                    Text(verbatim: model.bookLensAIStatusTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let account = model.accountSnapshot,
                       let rateLimit = account.primaryRateLimit {
                        Text(verbatim: limitText(rateLimit.remainingPercent, isLive: account.hasRateLimitSnapshot))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(verbatim: unavailableText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .help("Check Codex and account status again")
        .accessibilityLabel("ChatGPT status: \(model.bookLensAIStatusTitle)")
    }

    private var icon: String {
        model.canUseAI ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
    }

    private var color: Color {
        model.canUseAI ? .green : .orange
    }

    private var unavailableText: String {
        BookLensLocalization.string(
            model.codexState == .checking ? "Refreshing limit…" : "Limit temporarily unavailable"
        )
    }

    private func limitText(_ remainingPercent: Int, isLive: Bool) -> String {
        let prefix = BookLensLocalization.string("Limit")
        let staleSuffix = isLive ? "" : " · \(BookLensLocalization.string("previous"))"
        return "\(prefix): \(remainingPercent)%\(staleSuffix)"
    }
}
