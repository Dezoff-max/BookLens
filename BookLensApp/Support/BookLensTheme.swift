import AppKit
import SwiftUI

enum BookLensTheme {
    static let onboardingAccent = Color(red: 0.39, green: 0.19, blue: 0.96)

    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.88, green: 0.64, blue: 0.29, alpha: 1)
            : NSColor(red: 0.39, green: 0.20, blue: 0.93, alpha: 1)
    })
    static let blueAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.24, green: 0.28, blue: 0.34, alpha: 1)
            : NSColor(red: 0.34, green: 0.25, blue: 0.91, alpha: 1)
    })

    static let cardGradient = LinearGradient(
        colors: [
            Color.primary.opacity(0.055),
            Color.primary.opacity(0.018),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct BookLensCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.09))
            }
            .shadow(color: .black.opacity(0.055), radius: 8, y: 3)
    }
}

extension View {
    func bookLensCard() -> some View {
        modifier(BookLensCardModifier())
    }
}
