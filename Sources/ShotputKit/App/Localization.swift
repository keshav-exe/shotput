import Foundation

/// Returns the translation of a piece of interface text.
///
/// The key is the English string itself, so the two never drift apart: a key that has no
/// translation yet is shown in English, and a translation that is no longer used is easy to spot.
/// Translations live in `Resources/<language>.lproj/Localizable.strings`; see `docs/LOCALIZING.md`.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}
