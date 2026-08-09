import AppKit
import SwiftUI

struct AboutBookLensView: View {
    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text("BookLens")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text(versionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Turn local books into evidence-backed character profiles and artwork.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            VStack(spacing: 14) {
                aboutCard(
                    icon: "lock.shield.fill",
                    title: "Local-first by design",
                    description: "Your book files stay on your Mac. Data is sent only after your explicit confirmation."
                )

                aboutCard(
                    icon: "sparkles",
                    title: "Uses your ChatGPT subscription",
                    description: "BookLens connects through the installed Codex CLI. No API key or separate OpenAI API billing is used."
                )

                Link(destination: URL(string: "https://github.com/Dezoff-max/BookLens")!) {
                    Label("View BookLens on GitHub", systemImage: "arrow.up.right.square")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.link)
                .padding(.top, 2)

                Text("Source code available on GitHub")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .frame(width: 500)
        .background(.regularMaterial)
    }

    private func aboutCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BookLensTheme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
