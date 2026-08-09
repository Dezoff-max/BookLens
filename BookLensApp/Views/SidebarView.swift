import BookLensData
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    let books: [BookRecord]

    var body: some View {
        VStack(spacing: 0) {
            brand
            List(selection: $model.selectedSection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label {
                            Text(verbatim: section.title)
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                            .tag(section)
                    }
                }

                if !recentCharacters.isEmpty {
                    Section("Recent characters") {
                        ForEach(recentCharacters.prefix(6)) { character in
                            Button {
                                model.selectedBookID = character.book?.id
                                model.selectedCharacterID = character.id
                                model.selectedSection = .library
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(BookLensTheme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(character.name)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text(character.book?.title ?? character.role)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            accountCard
        }
        .navigationTitle("BookLens")
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 26))
                .foregroundStyle(BookLensTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("BookLens").font(.title3.bold())
                Text("Bring book characters to life")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: model.bookLensAIStatusTitle)
            } icon: {
                Image(systemName: codexStatusIcon)
            }
                .font(.callout.weight(.medium))
                .foregroundStyle(codexStatusColor)
            if let installation = model.codexInstallation {
                Text("Codex \(installation.version) · \(installation.architecture)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text("Model")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(verbatim: activeModelName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption)
            if let account = model.accountSnapshot,
               let rateLimit = account.primaryRateLimit {
                CodexLimitView(
                    rateLimit: rateLimit,
                    compact: true,
                    isStale: !account.hasRateLimitSnapshot
                )
                    .padding(.top, 2)
            } else {
                Label(limitUnavailableTitle, systemImage: "gauge.with.dots.needle.0percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.refreshCodex() }
        }
        .help("Check Codex and account status again")
    }

    private var recentCharacters: [CharacterRecord] {
        books
            .flatMap(\.characters)
            .filter { $0.isMainCharacter && !$0.isExcluded }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    private var activeModelName: String {
        model.selectedModel?.displayName ?? model.selectedModelID
    }

    private var limitUnavailableTitle: String {
        BookLensLocalization.string(
            model.codexState == .checking ? "Refreshing limit…" : "Limit temporarily unavailable"
        )
    }

    private var codexStatusIcon: String {
        switch model.codexState {
        case .available: "checkmark.seal.fill"
        case .notChecked: "circle.dotted"
        case .checking: "arrow.triangle.2.circlepath"
        case .loginRequired: "person.crop.circle.badge.exclamationmark"
        case .incompatible, .unavailable, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var codexStatusColor: Color {
        model.canUseAI ? .green : .secondary
    }
}
