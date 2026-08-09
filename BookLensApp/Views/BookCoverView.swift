import AppKit
import BookLensData
import SwiftUI

struct BookCoverView: View {
    let book: BookRecord
    let artwork: ArtworkRecord?
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if let image = coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if usesGeneratedArtwork {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    VStack {
                        Spacer()
                        VStack(spacing: 3) {
                            Text(book.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(3)
                            Text(book.author)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(10)
                    }
                }
            } else {
                BookCoverPlaceholder(title: book.title)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Book cover for “\(book.title)”")
    }

    private var usesGeneratedArtwork: Bool {
        guard artwork != nil else { return false }
        if let selected = book.coverArtworkID {
            return artwork?.id == selected
        }
        return book.coverPath.isEmpty || !FileManager.default.fileExists(atPath: book.coverPath)
    }

    private var coverImage: NSImage? {
        if let selected = book.coverArtworkID,
           artwork?.id == selected,
           let path = artwork?.storedPath,
           let image = NSImage(contentsOfFile: path)
        {
            return image
        }
        if !book.coverPath.isEmpty,
           let image = NSImage(contentsOfFile: book.coverPath)
        {
            return image
        }
        if let path = artwork?.storedPath {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }
}

struct BookCoverPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BookLensTheme.blueAccent, BookLensTheme.accent.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 28))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 7)
            }
            .foregroundStyle(.white)
        }
    }
}

func preferredCoverArtwork(for book: BookRecord, from artworks: [ArtworkRecord]) -> ArtworkRecord? {
    if let selected = book.coverArtworkID,
       let artwork = artworks.first(where: { $0.id == selected && $0.bookID == book.id })
    {
        return artwork
    }
    if !book.coverPath.isEmpty, FileManager.default.fileExists(atPath: book.coverPath) {
        return nil
    }
    return artworks
        .filter { $0.bookID == book.id && FileManager.default.fileExists(atPath: $0.storedPath) }
        .max { lhs, rhs in
            let lhsPriority = coverPriority(lhs)
            let rhsPriority = coverPriority(rhs)
            if lhsPriority == rhsPriority { return lhs.createdAt < rhs.createdAt }
            return lhsPriority < rhsPriority
        }
}

private func coverPriority(_ artwork: ArtworkRecord) -> Int {
    let compositionScore: Int
    switch artwork.composition {
    case "bookWorld": compositionScore = 500
    case "scene": compositionScore = 400
    case "fullBody": compositionScore = 300
    case "waistUp": compositionScore = 200
    case "portrait": compositionScore = 100
    default: compositionScore = 0
    }
    let favoriteScore = artwork.isFavorite ? 80 : 0
    let primaryScore = artwork.isPrimary ? 40 : 0
    return compositionScore + favoriteScore + primaryScore
}

struct BookClassificationBadges: View {
    let book: BookRecord
    var maximumGenres = 2

    var body: some View {
        HStack(spacing: 6) {
            badge(audienceTitle, icon: audienceIcon)
            if book.ageMin > 0 || book.ageMax > 0 {
                badge(ageTitle, icon: "person.2")
            }
            ForEach(book.genres.prefix(maximumGenres), id: \.self) { genre in
                badge(genre, icon: nil)
            }
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
    }

    private func badge(_ text: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var audienceTitle: String {
        switch BookAudience(storedValue: book.audience) {
        case .children: BookLensLocalization.string("Children")
        case .teen: BookLensLocalization.string("Teen")
        case .adult: BookLensLocalization.string("Adult")
        case .unspecified: BookLensLocalization.string("Uncategorized")
        }
    }

    private var audienceIcon: String {
        switch BookAudience(storedValue: book.audience) {
        case .children: "figure.and.child.holdinghands"
        case .teen: "person.2.fill"
        case .adult: "person.fill"
        case .unspecified: "questionmark.circle"
        }
    }

    private var ageTitle: String {
        if book.ageMin > 0, book.ageMax >= book.ageMin { return "\(book.ageMin)–\(book.ageMax)" }
        if book.ageMin > 0 { return "\(book.ageMin)+" }
        return "\(BookLensLocalization.string("until")) \(book.ageMax)"
    }
}
