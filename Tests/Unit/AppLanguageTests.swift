//
//  AppLanguageTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

@Suite("App language")
struct AppLanguageTests {
    @Test("Only the localizations the app ships are offered")
    func supportedCases() {
        #expect(AppLanguage.allCases == [.system, .english, .french])
    }

    @Test("Every case round-trips through its stored raw value")
    func rawValueRoundTrip() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage(rawValue: language.rawValue) == language)
        }
    }

    @Test("The system case follows the device locale rather than pinning one")
    func systemFollowsDevice() {
        #expect(AppLanguage.system.localeIdentifier == nil)
        #expect(AppLanguage.system.locale.identifier == Locale.autoupdatingCurrent.identifier)
    }

    @Test("Pinned cases publish the matching locale identifier")
    func pinnedLocales() {
        #expect(AppLanguage.english.localeIdentifier == "en")
        #expect(AppLanguage.french.localeIdentifier == "fr")
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.french.locale.identifier == "fr")
    }
}
