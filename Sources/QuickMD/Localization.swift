import Foundation

/// The app's own words in the user's language. English is the key;
/// other languages live in `Resources/Localization/<lang>.lproj`,
/// copied into the app by scripts/build-app.sh. A missing entry falls
/// back to the English key, so nothing ever shows blank.
func L(_ english: String) -> String {
    Bundle.main.localizedString(forKey: english, value: english, table: nil)
}

/// True when the app runs in Turkish (Help picks its text from this).
var isTurkish: Bool { Bundle.main.preferredLocalizations.first == "tr" }
