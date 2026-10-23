import Foundation
import Observation
import Combine

/// Display language is independent of document/OCR language and persisted report data.
enum UILanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, ko
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: return L("language.system")
        case .en: return L("language.en")
        case .ko: return L("language.ko")
        }
    }
}

indirect enum UIArgument: Sendable, Equatable {
    case verbatim(String)
    case count(Int)
    /// Technical coordinates and codes retain ungrouped source digits.
    case integer(Int)
    case message(UIMessage)
}

/// Keep keys and typed arguments until presentation, so existing state follows language changes.
struct UIMessage: Sendable, Equatable {
    fileprivate indirect enum Storage: Sendable, Equatable {
        case keyed(String, [UIArgument])
        case raw(String)
        case plural(String, Int)
        case joined([UIMessage], String)
    }
    fileprivate let storage: Storage

    init(_ key: StaticString, _ arguments: UIArgument...) {
        storage = .keyed(String(describing: key), arguments)
    }

    private init(_ storage: Storage) { self.storage = storage }
    static func raw(_ value: String) -> UIMessage { UIMessage(.raw(value)) }
    static func plural(_ base: StaticString, _ count: Int) -> UIMessage { UIMessage(.plural(String(describing: base), count)) }
    static func joined(_ messages: [UIMessage], separator: String) -> UIMessage { UIMessage(.joined(messages, separator)) }
    var isEmpty: Bool {
        switch storage {
        case .keyed(let key, _), .raw(let key), .plural(let key, _): return key.isEmpty
        case .joined(let messages, let separator): return messages.allSatisfy(\.isEmpty) && (messages.count < 2 || separator.isEmpty)
        }
    }
    @MainActor var text: String { LanguagePreferences.shared.localizer.render(self) }
}

/// An immutable display snapshot, safe to carry into non-main-actor work.
/// Only the explicitly named Reviset table is loaded; arbitrary user strings are never lookup keys.
struct Localizer: Sendable {
    let language: String
    private let translations: [String: String]
    private let english: [String: String]
    private let formats: DisplayFormatters

    init(language: String, bundle: Bundle = .main) {
        self.language = language == "ko" ? "ko" : "en"
        formats = DisplayFormatters(language: self.language)
        english = Self.loadTable(language: "en", bundle: bundle)
        translations = self.language == "en" ? english : Self.loadTable(language: self.language, bundle: bundle)
    }

    var locale: Locale { Locale(identifier: language == "ko" ? "ko_KR" : "en_US") }

    static func preferredLanguage(_ preferences: [String] = Locale.preferredLanguages) -> String {
        Bundle.preferredLocalizations(from: ["en", "ko"], forPreferences: preferences).first == "ko" ? "ko" : "en"
    }

    func render(_ message: UIMessage) -> String {
        switch message.storage {
        case .raw(let raw): return raw
        case .keyed(let key, let arguments): return renderKey(key, arguments: arguments)
        case .plural(let base, let count): return renderPlural(base, count)
        case .joined(let messages, let separator): return messages.map(render).joined(separator: separator)
        }
    }

    func string(_ key: StaticString, _ arguments: UIArgument...) -> String {
        renderKey(String(describing: key), arguments: arguments)
    }

    func plural(_ base: StaticString, _ count: Int) -> String {
        renderPlural(String(describing: base), count)
    }

    private func renderPlural(_ base: String, _ count: Int) -> String {
        let form = language == "en" && count == 1 ? "one" : "other"
        return renderKey("\(base).\(form)", arguments: [.count(count)])
    }

    func isoDate(_ raw: String) -> String { formats.isoDate(raw) }

    /// This closed mapping labels known codes only; an unknown code remains visible unchanged.
    func ocrLanguageCode(_ code: String) -> String {
        switch code {
        case "en", "en-US", "en-GB": return string("ocr.language.en")
        case "ko", "ko-KR": return string("ocr.language.ko")
        case "ja", "ja-JP": return string("ocr.language.ja")
        case "zh-Hans", "zh-Hans-CN": return string("ocr.language.zh_hans")
        case "zh-Hant", "zh-Hant-TW": return string("ocr.language.zh_hant")
        case "fr", "fr-FR": return string("ocr.language.fr")
        case "de", "de-DE": return string("ocr.language.de")
        case "es", "es-ES": return string("ocr.language.es")
        case "ar", "ar-SA": return string("ocr.language.ar")
        case "he", "he-IL": return string("ocr.language.he")
        default: return code
        }
    }

    private func renderKey(_ key: String, arguments: [UIArgument]) -> String {
        let template = translations[key] ?? english[key] ?? key
        let rendered = arguments.map { argument -> String in
            switch argument {
            case .verbatim(let value): return value
            case .message(let message): return render(message)
            case .integer(let value): return String(value)
            case .count(let value): return formats.count(value)
            }
        }
        // Scan the trusted template once. Inserted file names, source text and errors are opaque.
        var result = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}") {
                let start = template.index(after: cursor)
                let number = template[start..<end]
                if !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }),
                   let index = Int(number), rendered.indices.contains(index) {
                    result += rendered[index]
                    cursor = template.index(after: end)
                    continue
                }
            }
            result.append(template[cursor])
            cursor = template.index(after: cursor)
        }
        return result
    }

    private static func loadTable(language: String, bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: "Reviset", withExtension: "strings", subdirectory: nil, localization: language),
              let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        else { return [:] }
        return table
    }
}

// Formatters are shared by immutable snapshots. Serialize their mutable Foundation
// internals rather than expose non-Sendable formatter instances across actors.
private final class DisplayFormatters: @unchecked Sendable {
    private let lock = NSLock()
    private let number = NumberFormatter()
    private let date = DateFormatter()
    private let fractionalISO = ISO8601DateFormatter()
    private let ordinaryISO = ISO8601DateFormatter()
    init(language: String) {
        let locale = Locale(identifier: language == "ko" ? "ko_KR" : "en_US")
        number.locale = locale; number.numberStyle = .decimal; number.maximumFractionDigits = 0
        date.locale = locale; date.timeZone = .autoupdatingCurrent; date.dateStyle = .medium; date.timeStyle = .short
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        ordinaryISO.formatOptions = [.withInternetDateTime]
    }
    func count(_ value: Int) -> String { lock.withLock { number.string(from: NSNumber(value: value)) ?? String(value) } }
    func isoDate(_ raw: String) -> String {
        lock.withLock {
            guard let value = fractionalISO.date(from: raw) ?? ordinaryISO.date(from: raw) else { return raw }
            return date.string(from: value)
        }
    }
}

@MainActor @Observable final class LanguagePreferences: @MainActor ObservableObject {
    static let shared = LanguagePreferences()
    static let preferenceKey = "RevisetUILanguage"
    // Commands/Scene use Combine invalidation; view bodies also track Observation.
    @ObservationIgnored let objectWillChange = ObservableObjectPublisher()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundle: Bundle
    var selection: UILanguage {
        didSet {
            objectWillChange.send()
            defaults.set(selection.rawValue, forKey: Self.preferenceKey)
            localizer = Localizer(language: selection == .system ? Localizer.preferredLanguage() : selection.rawValue, bundle: bundle)
        }
    }
    private(set) var localizer: Localizer
    var effectiveLanguage: String { localizer.language }

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        let initialSelection = UILanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        selection = initialSelection
        localizer = Localizer(language: initialSelection == .system ? Localizer.preferredLanguage() : initialSelection.rawValue, bundle: bundle)
    }
}

@MainActor func L(_ key: StaticString, _ arguments: UIArgument...) -> String {
    LanguagePreferences.shared.localizer.render(UIMessage.forwarded(key, arguments))
}

@MainActor func LC(_ base: StaticString, _ count: Int) -> String {
    LanguagePreferences.shared.localizer.plural(base, count)
}

@MainActor func localizedISODate(_ raw: String) -> String { LanguagePreferences.shared.localizer.isoDate(raw) }
@MainActor func localizedOCRLanguageCode(_ code: String) -> String { LanguagePreferences.shared.localizer.ocrLanguageCode(code) }

private extension UIMessage {
    static func forwarded(_ key: StaticString, _ arguments: [UIArgument]) -> UIMessage {
        UIMessage(.keyed(String(describing: key), arguments))
    }
}
