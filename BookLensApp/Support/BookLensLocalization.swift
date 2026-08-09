import Foundation
import Observation

@Observable
private final class BookLensLocalizationState: @unchecked Sendable {
    var revision = 0
}

enum BookLensLocalization {
    private final class BundleMarker {}
    private static let state = BookLensLocalizationState()

    static func string(_ key: String) -> String {
        // Reading the observable revision makes every SwiftUI body that uses
        // this helper participate in runtime language updates. The localized
        // value itself stays backed by UserDefaults so command menus, sheets,
        // and tests all use the same persisted preference.
        _ = state.revision
        let preference = UserDefaults.standard.string(forKey: "languagePreference") ?? "system"
        let language = resolvedLanguage(for: normalizedPreference(preference))

        for container in candidateBundles() {
            guard let path = container.path(forResource: language, ofType: "lproj"),
                  let languageBundle = Bundle(path: path)
            else {
                continue
            }
            return NSLocalizedString(key, bundle: languageBundle, value: key, comment: "")
        }
        return key
    }

    static func locale(for preference: String) -> Locale {
        Locale(identifier: resolvedLanguage(for: preference))
    }

    static func normalizedPreference(_ preference: String) -> String {
        switch preference {
        case "ru", "en", "system": preference
        default: "system"
        }
    }

    static func languagePreferenceDidChange() {
        state.revision &+= 1
    }

    static func resolvedLanguage(for preference: String) -> String {
        let normalizedPreference = normalizedPreference(preference)
        if normalizedPreference == "ru" || normalizedPreference == "en" {
            return normalizedPreference
        }
        return Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    }

    private static func candidateBundles() -> [Bundle] {
        let moduleBundleName = "BookLens_BookLens.bundle"
        let markerBundle = Bundle(for: BundleMarker.self)
        let searchRoots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            markerBundle.resourceURL,
            markerBundle.bundleURL,
            markerBundle.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        var bundles = [Bundle.main]
        var seenPaths = Set([Bundle.main.bundleURL.standardizedFileURL.path])
        for root in searchRoots {
            let candidateURL = root
                .appendingPathComponent(moduleBundleName, isDirectory: true)
                .standardizedFileURL
            guard seenPaths.insert(candidateURL.path).inserted,
                  let bundle = Bundle(url: candidateURL)
            else {
                continue
            }
            bundles.append(bundle)
        }
        return bundles
    }
}
