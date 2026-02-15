import Foundation

struct AppLanguage: Identifiable, Hashable {
    static let systemCode = "system"
    static let system = AppLanguage(code: systemCode)

    let code: String

    var id: String { code }

    var locale: Locale {
        isSystem ? .autoupdatingCurrent : Locale(identifier: code)
    }

    var isSystem: Bool {
        code == Self.systemCode
    }

    var displayName: String {
        if isSystem {
            return translate("settings.language.system")
        }

        return Self.localizedName(for: code)
    }

    init(code: String) {
        self.code = Self.normalizeLanguageCode(code)
    }

    static var available: [AppLanguage] {
        [system] + availableLanguageCodes.map { AppLanguage(code: $0) }
    }

    static var supportedLanguageCodes: Set<String> {
        Set(availableLanguageCodes)
    }

    static var fallbackLanguageCode: String? {
        if let dev = Bundle.module.developmentLocalization.map(normalizeLanguageCode),
           supportedLanguageCodes.contains(dev) {
            return dev
        }

        return availableLanguageCodes.first
    }

    static func fromStored(_ storedValue: String?) -> AppLanguage {
        guard let storedValue else { return .system }

        let normalized = normalizeLanguageCode(storedValue)
        if normalized == systemCode {
            return .system
        }

        if supportedLanguageCodes.contains(normalized) {
            return AppLanguage(code: normalized)
        }

        return .system
    }

    static func resolvedLanguageCode(for selectedLanguage: AppLanguage) -> String {
        if !selectedLanguage.isSystem {
            return selectedLanguage.code
        }

        for preferred in Locale.preferredLanguages {
            let base = normalizeLanguageCode(preferred)
            if supportedLanguageCodes.contains(base) {
                return base
            }
        }

        return fallbackLanguageCode ?? availableLanguageCodes.first ?? systemCode
    }

    static func isValidStorageValue(_ storedValue: String) -> Bool {
        let normalized = normalizeLanguageCode(storedValue)
        return normalized == systemCode || supportedLanguageCodes.contains(normalized)
    }

    private static var availableLanguageCodes: [String] {
        let normalizedCodes = Bundle.module.localizations
            .map(normalizeLanguageCode)
            .filter { !$0.isEmpty && $0 != "base" && $0 != systemCode }

        let unique = Array(Set(normalizedCodes))
        return unique.sorted { localizedName(for: $0) < localizedName(for: $1) }
    }

    private static func normalizeLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == systemCode {
            return systemCode
        }

        return String(normalized.split(separator: "-").first ?? Substring(normalized))
    }

    private static func localizedName(for code: String) -> String {
        let locale = Locale.current
        let localized = locale.localizedString(forLanguageCode: code)
            ?? Locale(identifier: code).localizedString(forLanguageCode: code)
            ?? code

        return localized.capitalized(with: locale)
    }
}
