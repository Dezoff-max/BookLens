import BookLensDomain
import SwiftUI

struct CodexLimitView: View {
    @Environment(\.locale) private var locale

    let rateLimit: CodexRateLimitSnapshot
    var compact = false
    var isStale = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label {
                        Text(verbatim: "\(localized("Remaining")) \(rateLimit.remainingPercent)%")
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    }
                    Spacer()
                    if let resetText {
                        Text(verbatim: "\(localized("until")) \(resetText)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                ProgressView(value: Double(rateLimit.remainingPercent), total: 100)
                    .tint(rateLimit.remainingPercent <= 20 ? .orange : BookLensTheme.accent)
                    .accessibilityLabel(Text(verbatim: localized("Remaining limit")))
                    .accessibilityValue(Text(verbatim: "\(rateLimit.remainingPercent) \(localized("percent"))"))
                if isStale {
                    Label("Last available data", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Label(localized("Remaining limit"), systemImage: "gauge.with.dots.needle.33percent")
                        .font(.headline)
                    Spacer()
                    Text("\(rateLimit.remainingPercent)%")
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                ProgressView(value: Double(rateLimit.remainingPercent), total: 100)
                    .tint(rateLimit.remainingPercent <= 20 ? .orange : BookLensTheme.accent)
                    .accessibilityLabel(Text(verbatim: localized("Remaining limit")))
                    .accessibilityValue(Text(verbatim: "\(rateLimit.remainingPercent) \(localized("percent"))"))
                HStack {
                    Text(windowTitle)
                    Spacer()
                    if let resetText {
                        Text(verbatim: "\(localized("Reset")): \(resetText)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if isStale {
                    Label("The server did not refresh the limit — showing the last available data", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var windowTitle: String {
        switch rateLimit.windowDurationMinutes {
        case 10_080: localized("Weekly")
        case 1_440: localized("Daily")
        case 300: localized("5-hour limit")
        case let minutes?: "\(localized("Window")) \(minutes / 60) \(localized("h"))"
        case nil: localized("Current window")
        }
    }

    private var resetText: String? {
        rateLimit.resetsAt?.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
                .locale(locale)
        )
    }

    private func localized(_ key: String) -> String {
        BookLensLocalization.string(key)
    }
}
