import Foundation

func configureLegacyNativeLocalization() {
    // Registration is process-local; do not persist or alter the user's app language.
    UserDefaults.standard.register(defaults:["RevisetUILanguage":"ko"])
}
