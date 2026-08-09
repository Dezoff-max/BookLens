import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case books
    case characters
    case studio
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: BookLensLocalization.string("Home")
        case .books: BookLensLocalization.string("My books")
        case .characters: BookLensLocalization.string("Characters")
        case .studio: BookLensLocalization.string("Create image")
        case .gallery: BookLensLocalization.string("My images")
        }
    }

    var systemImage: String {
        switch self {
        case .library: "house"
        case .books: "books.vertical.fill"
        case .characters: "person.crop.rectangle.stack"
        case .studio: "paintbrush.pointed"
        case .gallery: "photo.on.rectangle.angled"
        }
    }
}

enum CharacterCreationMode: String, CaseIterable, Identifiable {
    case portrait
    case fullBody
    case scene
    case bookWorld

    var id: String { rawValue }
}
