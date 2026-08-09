import BookLensData
import SwiftData
import SwiftUI

struct BookClassificationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let book: BookRecord

    @State private var audience: BookAudience
    @State private var includesAge: Bool
    @State private var ageMin: Int
    @State private var ageMax: Int
    @State private var genresText: String

    init(book: BookRecord) {
        self.book = book
        _audience = State(initialValue: BookAudience(storedValue: book.audience))
        _includesAge = State(initialValue: book.ageMin > 0 || book.ageMax > 0)
        _ageMin = State(initialValue: max(book.ageMin, 0))
        _ageMax = State(initialValue: max(max(book.ageMax, book.ageMin), 0))
        _genresText = State(initialValue: book.genres.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: localized("Book classification"))
                        .font(.title2.bold())
                    Text(book.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Text(verbatim: localized("Close"))
                }
            }

            Form {
                Picker(selection: $audience) {
                    Text(verbatim: localized("Uncategorized")).tag(BookAudience.unspecified)
                    Text(verbatim: localized("Children")).tag(BookAudience.children)
                    Text(verbatim: localized("Teen")).tag(BookAudience.teen)
                    Text(verbatim: localized("Adult")).tag(BookAudience.adult)
                } label: {
                    Text(verbatim: localized("Audience"))
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $includesAge) {
                    Text(verbatim: localized("Specify recommended age"))
                }
                if includesAge {
                    Stepper(value: $ageMin, in: 0...99) {
                        Text(verbatim: String(format: localized("From age %lld"), Int64(ageMin)))
                    }
                        .onChange(of: ageMin) { _, value in
                            if ageMax < value { ageMax = value }
                        }
                    Stepper(value: $ageMax, in: ageMin...99) {
                        Text(verbatim: String(format: localized("Up to age %lld"), Int64(ageMax)))
                    }
                }

                TextField(localized("Genres, comma-separated"), text: $genresText)
                Text(verbatim: localized("AI classification is a library recommendation, not an official age rating."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                if book.classificationConfidence != "unspecified" {
                    Label(confidenceTitle, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Text(verbatim: localized("Cancel"))
                }
                Button(action: { save() }) {
                    Text(verbatim: localized("Save"))
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620, height: 460)
    }

    private var confidenceTitle: String {
        if book.classificationConfidence == "manual" { return BookLensLocalization.string("Edited manually") }
        return BookLensLocalization.string("Suggested by AI")
    }

    private func localized(_ key: String) -> String {
        BookLensLocalization.string(key)
    }

    private func save() {
        book.audience = audience.rawValue
        book.ageMin = includesAge ? ageMin : 0
        book.ageMax = includesAge ? max(ageMax, ageMin) : 0
        var seen = Set<String>()
        book.genres = genresText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(4)
            .map { $0 }
        book.classificationConfidence = "manual"
        try? modelContext.save()
        dismiss()
    }
}
