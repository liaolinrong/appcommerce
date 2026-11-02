import CommerceCore
import Foundation
import Testing
@testable import CommerceUI

struct CommerceLocalizationTests {
    @Test
    func supportedLanguagesAndKeys() {
        #expect(CommerceLanguage.allCases.count == 15)
        #expect(Set(CommerceLanguage.allCases.map(\.rawValue)) == [
            "en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es",
            "pt-BR", "pt-PT", "it", "nl", "pl", "tr", "id"
        ])
        #expect(CommerceTextKey.allCases.count == 12)
        #expect(Set(CommerceTextKey.allCases.map(\.rawValue)) == [
            "checking", "notStarted", "trial", "unlocked", "expired", "busy",
            "verificationFailed", "unexpectedProduct", "productUnavailable",
            "trialAlreadyUsed", "alreadyUnlocked", "providerFailure"
        ])
        #expect(Set(CommerceLocalization.tables.keys) == Set(CommerceLanguage.allCases))
    }

    @Test(arguments: CommerceLanguage.allCases)
    func everyLanguageHasEveryKey(language: CommerceLanguage) {
        #expect(Set(CommerceLocalization.tables[language]?.keys.map { $0 } ?? []) == Set(CommerceTextKey.allCases.map(\.rawValue)))
        for key in CommerceTextKey.allCases {
            let value = CommerceLocalization.text(key, language: language)
            #expect(!value.isEmpty)
            #expect(value != key.rawValue)
            if language != .english {
                #expect(value != CommerceLocalization.text(key, language: .english))
            }
            if key == .trial {
                #expect(value.components(separatedBy: "%@").count == 2)
                #expect(!value.replacingOccurrences(of: "%@", with: "").contains("%"))
            } else {
                #expect(!value.contains("%"))
            }
        }
    }

    @Test(arguments: CommerceLanguage.allCases)
    func trialDateInterpolation(language: CommerceLanguage) {
        let date = "2026-10-24 09:30"
        let template = CommerceLocalization.text(.trial, language: language)
        #expect(template.components(separatedBy: "%@").count == 2)
        let message = CommerceLocalization.trial(expiresAt: date, language: language)
        #expect(message.contains(date))
        #expect(!message.contains("%@"))
        let expected: [CommerceLanguage: String] = [
            .english: "Trial expires on \(date)",
            .simplifiedChinese: "试用将于 \(date) 到期",
            .traditionalChinese: "試用將於 \(date) 到期",
            .japanese: "試用期間は \(date) に終了します",
            .korean: "체험은 \(date)에 종료됩니다",
            .french: "L’essai expire le \(date)",
            .german: "Der Testzeitraum endet am \(date)",
            .spanish: "La prueba caduca el \(date)",
            .brazilianPortuguese: "O período de teste termina em \(date)",
            .europeanPortuguese: "O período de avaliação termina em \(date)",
            .italian: "La prova scade il \(date)",
            .dutch: "De proefperiode verloopt op \(date)",
            .polish: "Okres próbny wygasa \(date)",
            .turkish: "Deneme süresi \(date) tarihinde sona erer",
            .indonesian: "Uji coba berakhir pada \(date)"
        ]
        #expect(message == expected[language])
        let literalDate = "date with %@ and %d"
        #expect(CommerceLocalization.trial(expiresAt: literalDate, language: language) == template.replacingOccurrences(of: "%@", with: literalDate))
    }

    @Test(arguments: CommerceLanguage.allCases)
    func allStatesAndErrorsAreLocalized(language: CommerceLanguage) {
        let states: [(AccessState, CommerceTextKey)] = [
            (.checking, .checking), (.notStarted, .notStarted),
            (.unlocked, .unlocked), (.expired, .expired)
        ]
        for (state, key) in states {
            let text = CommerceLocalization.status(state, language: language)
            #expect(text == CommerceLocalization.text(key, language: language))
        }
        let expiration = Date(timeIntervalSince1970: 0)
        let date = expiration.formatted(.dateTime.locale(Locale(identifier: language.rawValue)))
        #expect(CommerceLocalization.status(.trial(expiresAt: expiration), language: language) == CommerceLocalization.trial(expiresAt: date, language: language))
        let errors: [(CommerceError, CommerceTextKey)] = [
            (.verificationFailed, .verificationFailed), (.unexpectedProduct, .unexpectedProduct),
            (.productUnavailable, .productUnavailable), (.trialAlreadyUsed, .trialAlreadyUsed),
            (.alreadyUnlocked, .alreadyUnlocked),
            (.providerFailure(message: "raw diagnostic must not be shown"), .providerFailure)
        ]
        for (error, key) in errors {
            let text = CommerceLocalization.error(error, language: language)
            #expect(text == CommerceLocalization.text(key, language: language))
            #expect(!text.contains("raw diagnostic"))
        }
    }
}