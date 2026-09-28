//
//  AppViewModelTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// The app-scoped model: settings, and remembering which folder to reopen.
@Suite("App view model")
@MainActor
struct AppViewModelTests {
    // MARK: - Settings

    @Test("Settings are read from the store when the app starts")
    func loadsStoredPreferences() {
        let stored = AppPreferences(language: .french, theme: .dark)
        let app = makeAppViewModel(preferences: InMemoryPreferencesStore(initial: stored))

        #expect(app.preferences == stored)
    }

    @Test("Changing the language persists it immediately")
    func persistsLanguage() {
        let store = InMemoryPreferencesStore()
        let app = makeAppViewModel(preferences: store)

        app.setLanguage(.french)

        #expect(app.preferences.language == .french)
        #expect(store.stored.language == .french)
    }

    @Test("Changing the appearance persists it immediately")
    func persistsTheme() {
        let store = InMemoryPreferencesStore()
        let app = makeAppViewModel(preferences: store)

        app.setTheme(.dark)

        #expect(app.preferences.theme == .dark)
        #expect(store.stored.theme == .dark)
    }

    @Test("Setting a value to what it already is does not touch the store")
    func skipsRedundantWrites() {
        let store = InMemoryPreferencesStore()
        let app = makeAppViewModel(preferences: store)

        app.setLanguage(.system)
        app.setTheme(.system)

        #expect(store.saves == 0)
    }

    // MARK: - Remembering a folder

    @Test("Opening a folder forwards the request and remembers it")
    func opensAndRemembersFolder() async throws {
        let bookmarks = InMemoryBookmarkStore()
        let access = StubFolderAccess(folder: .fixture())
        let app = makeAppViewModel(bookmarks: bookmarks, folderAccess: access)

        let folder = try await app.openFolder(at: AuthorizedFolder.fixtureURL)

        let requested = await access.requestedURLs
        #expect(folder == .fixture())
        #expect(requested == [AuthorizedFolder.fixtureURL])
        #expect(bookmarks.storedBookmark == AuthorizedFolder.fixture().bookmark)
    }

    @Test("A folder that cannot be remembered still opens")
    func unrememberableFolderStillOpens() async throws {
        let bookmarks = InMemoryBookmarkStore()
        let app = makeAppViewModel(
            bookmarks: bookmarks,
            folderAccess: StubFolderAccess(folder: .fixture(bookmark: nil))
        )

        let folder = try await app.openFolder(at: AuthorizedFolder.fixtureURL)

        // Nothing to remember, and nothing worth interrupting the user about —
        // the folder itself is open.
        #expect(folder.bookmark == nil)
        #expect(bookmarks.storedBookmark == nil)
    }

    @Test("A folder that cannot be opened surfaces the service error")
    func propagatesOpenFailure() async {
        let app = makeAppViewModel(
            folderAccess: StubFolderAccess(folder: .fixture(), failure: .accessDenied)
        )

        await #expect(throws: FolderAccessError.accessDenied) {
            try await app.openFolder(at: AuthorizedFolder.fixtureURL)
        }
    }

    @Test("Forgetting the remembered folder clears it")
    func forgetsRememberedFolder() {
        let bookmarks = InMemoryBookmarkStore(bookmark: Data([0x11]))
        let app = makeAppViewModel(bookmarks: bookmarks)

        app.forgetRememberedFolder()

        #expect(bookmarks.storedBookmark == nil)
    }
}
