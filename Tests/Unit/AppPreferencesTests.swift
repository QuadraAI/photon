//
//  AppPreferencesTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

@Suite("App preferences")
struct AppPreferencesTests {
    @Test("Defaults follow the device language and appearance")
    func defaults() {
        let preferences = AppPreferences()

        #expect(preferences.language == .system)
        #expect(preferences.theme == .system)
    }

    @Test("A fresh store reports the defaults")
    func emptyStoreLoadsDefaults() {
        let store = UserDefaultsPreferencesStore(defaults: .isolated())

        #expect(store.load() == AppPreferences())
    }

    @Test("Every setting survives a save and load round trip")
    func roundTrip() {
        let store = UserDefaultsPreferencesStore(defaults: .isolated())
        let written = AppPreferences(language: .french, theme: .dark)

        store.save(written)

        #expect(store.load() == written)
    }

    @Test("A key the user never set keeps the default rather than collapsing")
    func unsetKeysKeepDefaults() {
        let store = UserDefaultsPreferencesStore(defaults: .isolated())

        store.save(AppPreferences(language: .english))

        // The theme was never chosen, so it must stay on `.system` instead of
        // being written back as some arbitrary concrete value.
        #expect(store.load().theme == .system)
    }

    @Test("Unreadable stored values fall back to the defaults instead of crashing")
    func corruptValuesFallBack() {
        let defaults = UserDefaults.isolated()
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.save(AppPreferences(language: .french, theme: .dark))

        // Corrupt whatever keys the store actually wrote rather than repeating
        // its private key names here — hardcoding them would let this test pass
        // vacuously if they ever changed.
        for key in defaults.dictionaryRepresentation().keys {
            defaults.set("klingon", forKey: key)
        }

        #expect(store.load() == AppPreferences())
    }
}

@Suite("Remembered folder bookmark")
struct BookmarkStoreTests {
    @Test("Nothing is remembered to begin with")
    func emptyByDefault() {
        let store = UserDefaultsBookmarkStore(defaults: .isolated())

        #expect(store.loadBookmark() == nil)
    }

    @Test("A bookmark survives a save and load round trip")
    func roundTrip() {
        let store = UserDefaultsBookmarkStore(defaults: .isolated())
        let bookmark = Data([0x01, 0x02, 0x03])

        store.saveBookmark(bookmark)

        #expect(store.loadBookmark() == bookmark)
    }

    @Test("Saving nil forgets the folder")
    func clearingForgets() {
        let store = UserDefaultsBookmarkStore(defaults: .isolated())
        store.saveBookmark(Data([0x01]))

        store.saveBookmark(nil)

        #expect(store.loadBookmark() == nil)
    }
}

extension UserDefaults {
    /// A throwaway defaults domain so tests never touch the real app domain.
    static func isolated() -> UserDefaults {
        // The suite name is registered as a strong reference by `UserDefaults`
        // for the lifetime of the process, which is exactly what a test wants.
        UserDefaults(suiteName: "com.quadra.PhotonTests.\(UUID().uuidString)") ?? .standard
    }
}
