import CommerceCore
import Foundation

public enum CommerceLanguage: String, Sendable, CaseIterable, Hashable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case brazilianPortuguese = "pt-BR"
    case europeanPortuguese = "pt-PT"
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case indonesian = "id"
}

enum CommerceTextKey: String, CaseIterable {
    case checking, notStarted, trial, unlocked, expired, busy
    case verificationFailed, unexpectedProduct, productUnavailable
    case trialAlreadyUsed, alreadyUnlocked, providerFailure
}

enum CommerceLocalization {
    static let tables: [CommerceLanguage: [String: String]] = Dictionary(
        uniqueKeysWithValues: CommerceLanguage.allCases.map { language in
            let url = Bundle.module.bundleURL
                .appendingPathComponent("\(language.rawValue.lowercased()).lproj")
                .appendingPathComponent("Commerce.strings")
            guard let data = try? Data(contentsOf: url),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
                preconditionFailure("Missing commerce localization: \(language.rawValue)")
            }
            return (language, table)
        }
    )

    static func text(_ key: CommerceTextKey, language: CommerceLanguage) -> String {
        guard let value = tables[language]?[key.rawValue] else {
            preconditionFailure("Missing commerce text: \(language.rawValue)/\(key.rawValue)")
        }
        return value
    }

    static func trial(expiresAt: String, language: CommerceLanguage) -> String {
        String(format: text(.trial, language: language), locale: Locale(identifier: language.rawValue), expiresAt)
    }

    static func status(_ state: AccessState, language: CommerceLanguage) -> String {
        switch state {
        case .checking: text(.checking, language: language)
        case .notStarted: text(.notStarted, language: language)
        case .unlocked: text(.unlocked, language: language)
        case .expired: text(.expired, language: language)
        case .trial(let expiration):
            trial(expiresAt: expiration.formatted(.dateTime.locale(Locale(identifier: language.rawValue))), language: language)
        }
    }

    static func error(_ error: CommerceError, language: CommerceLanguage) -> String {
        let key: CommerceTextKey
        switch error {
        case .verificationFailed: key = .verificationFailed
        case .unexpectedProduct: key = .unexpectedProduct
        case .productUnavailable: key = .productUnavailable
        case .trialAlreadyUsed: key = .trialAlreadyUsed
        case .alreadyUnlocked: key = .alreadyUnlocked
        case .providerFailure: key = .providerFailure
        }
        return text(key, language: language)
    }
}