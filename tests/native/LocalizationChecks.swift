import Foundation

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        let english = Localizer(language: "en")
        let korean = Localizer(language: "ko")
        precondition(english.string("test.greeting", .verbatim("Ada")) == "Hello, Ada")
        precondition(korean.string("test.greeting", .verbatim("Ada")) == "안녕하세요, Ada")
        precondition(english.plural("test.items", 0) == "0 items")
        precondition(english.plural("test.items", 1) == "1 item")
        precondition(english.plural("test.items", 2) == "2 items")
        precondition(korean.plural("test.items", 0) == "0개")
        precondition(korean.plural("test.items", 1) == "1개")
        precondition(korean.plural("test.items", 2) == "2개")
        precondition(english.plural("test.items", 1234) == "1,234 items")
        precondition(english.string("test.wrap", .integer(1234)) == "[1234]")
        precondition(korean.string("test.wrap", .integer(1234)) == "[1234]")

        let literal = #"test.greeting %@ %% {0} {1} \" data"# + "\nمرحبا 한글"
        precondition(english.string("test.wrap", .verbatim(literal)) == "[\(literal)]")
        precondition(english.render(.raw("test.greeting")) == "test.greeting")
        precondition(english.render(.raw(literal)) == literal)
        precondition(english.string("test.nested", .message(UIMessage("test.wrap", .verbatim(literal))), .verbatim("{0}")) == "[\(literal)] / {0}")
        precondition(english.string("test.percent", .verbatim(literal)) == "%@ %% \(literal)")
        precondition(english.string("test.escape") == "Quoted \"value\" \\ path\nnext\ttab")
        precondition(UIMessage.raw("").isEmpty)
        precondition(!UIMessage.raw("0").isEmpty)
        precondition(UIMessage.joined([], separator: " · ").isEmpty)

        // This deliberately incomplete test resource simulates a missing translated entry.
        precondition(korean.string("test.fallback") == "English fallback")
        precondition(korean.string("test.absent_key") == "test.absent_key")
        let injectedBundle = Bundle(path: CommandLine.arguments[1])!
        precondition(Localizer(language: "ko", bundle: injectedBundle).string("test.greeting", .verbatim("Ada")) == "안녕하세요, Ada")
        precondition(Localizer(language: "fr", bundle: injectedBundle).language == "en")
        precondition(Localizer.preferredLanguage(["ko-KR", "en-US"]) == "ko")
        precondition(Localizer.preferredLanguage(["ja-JP"]) == "en")
        precondition(Localizer.preferredLanguage(["en-GB", "ko-KR"]) == "en")

        let suiteName = "org.reviset.localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["ja-JP", "ko-KR"], forKey: "AppleLanguages")
        let preferences = LanguagePreferences(defaults: defaults, bundle: injectedBundle)
        precondition(preferences.selection == .system)
        preferences.selection = .ko
        precondition(preferences.effectiveLanguage == "ko")
        precondition(LanguagePreferences(defaults: defaults, bundle: injectedBundle).selection == .ko)
        precondition(defaults.stringArray(forKey: "AppleLanguages") == ["ja-JP", "ko-KR"])
        preferences.selection = .en
        precondition(preferences.localizer.string("test.greeting", .verbatim("Ada")) == "Hello, Ada")
        defaults.set("unsupported", forKey: LanguagePreferences.preferenceKey)
        precondition(LanguagePreferences(defaults: defaults, bundle: injectedBundle).selection == .system)

        let shared = LanguagePreferences.shared
        let previous = shared.selection
        let domain = Bundle.main.bundleIdentifier ?? "org.reviset.localization-checks"
        let persisted = UserDefaults.standard.persistentDomain(forName:domain)?[LanguagePreferences.preferenceKey]
        defer {
            shared.selection = previous
            if let persisted { UserDefaults.standard.set(persisted,forKey:LanguagePreferences.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey:LanguagePreferences.preferenceKey) }
        }
        let saved = UIMessage.joined([UIMessage("test.greeting", .verbatim(literal)), .plural("test.items", 1)], separator: " · ")
        shared.selection = .en
        precondition(saved.text == "Hello, \(literal) · 1 item")
        precondition(L("test.wrap", .verbatim(literal)) == "[\(literal)]")
        precondition(LC("test.items", 2) == "2 items")
        shared.selection = .ko
        precondition(saved.text == "안녕하세요, \(literal) · 1개")
        precondition(LC("test.items", 2) == "2개")
        precondition(english.render(saved) == "Hello, \(literal) · 1 item")
        precondition(localizedOCRLanguageCode("ko-KR") == "한국어")
        precondition(localizedOCRLanguageCode("en-US") == "영어")
        precondition(localizedOCRLanguageCode("ja-JP") == "일본어")
        precondition(localizedOCRLanguageCode("unknown-%@-{0}") == "unknown-%@-{0}")
        precondition(localizedISODate("not-an-iso-date %@ {0}") == "not-an-iso-date %@ {0}")
        precondition(!localizedISODate("2026-10-23T01:23:45.678Z").contains("T01:23:45"))
        precondition(english.isoDate("2026-10-23T01:23:45Z") != korean.isoDate("2026-10-23T01:23:45Z"))
        print("PASS localization: immutable snapshots, live typed state, plurals, fallback, opaque data and isolated preference persistence")
    }
}
