//
//  LaunchTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// The launch decision, which is app-scoped: it happens once per launch and only
/// the first window gets to see it.
@Suite("Launch")
@MainActor
struct LaunchTests {
    @Test("A first run settles on the welcome screen with no placeholder")
    func firstRunShowsWelcome() {
        let app = makeAppViewModel()
        let window = FolderViewModel(app: app)

        // Nothing is remembered, so there is nothing to wait for.
        #expect(app.isLaunchPending == false)
        #expect(window.phase == .welcome(notice: nil))
    }

    @Test("A remembered folder leaves the window undecided until it resolves")
    func rememberedFolderStartsUndecided() async {
        let app = makeAppViewModel(bookmarks: InMemoryBookmarkStore(bookmark: Data([0x11])))
        let window = FolderViewModel(app: app)

        // Showing the welcome screen here and snatching it away would flash the
        // wrong screen at launch.
        #expect(window.phase == .starting)

        await window.start()
        #expect(window.phase != .starting)
    }

    @Test("A remembered folder is reopened and the welcome screen is skipped")
    func reopensRememberedFolder() async {
        let folder = AuthorizedFolder.fixture(name: "Holidays")
        let bookmarks = InMemoryBookmarkStore(bookmark: Data([0x11]))
        let app = makeAppViewModel(
            bookmarks: bookmarks,
            folderAccess: StubFolderAccess(folder: folder)
        )
        let window = FolderViewModel(app: app)

        await window.start()

        #expect(window.phase == .editing(AuthorizedFolder(url: folder.url, bookmark: Data([0x11]))))
        // `restore` can hand back a refreshed bookmark, so it is always stored.
        #expect(bookmarks.storedBookmark == Data([0x11]))
    }

    @Test("A bookmark that no longer resolves is explained rather than silently dropped")
    func explainsUnresolvableBookmark() async {
        let bookmarks = InMemoryBookmarkStore(bookmark: Data([0x11]))
        let app = makeAppViewModel(
            bookmarks: bookmarks,
            folderAccess: StubFolderAccess(folder: .fixture(), failure: .bookmarkResolutionFailed)
        )
        let window = FolderViewModel(app: app)

        await window.start()

        #expect(window.phase == .welcome(notice: .rememberedFolderUnavailable))
        // Kept: a folder on an unplugged drive looks exactly like a deleted one,
        // and forgetting it would lose the memory for when the volume returns.
        #expect(bookmarks.storedBookmark == Data([0x11]))
    }

    @Test("The user can forget the folder Photon could not reopen")
    func forgetsUnreopenableFolder() async {
        let bookmarks = InMemoryBookmarkStore(bookmark: Data([0x11]))
        let app = makeAppViewModel(
            bookmarks: bookmarks,
            folderAccess: StubFolderAccess(folder: .fixture(), failure: .bookmarkResolutionFailed)
        )
        let window = FolderViewModel(app: app)
        await window.start()

        window.forgetRememberedFolder()

        #expect(bookmarks.storedBookmark == nil)
        #expect(window.phase == .welcome(notice: nil))
    }

    // MARK: - One launch, one restore

    @Test("Restoring only runs once, however many windows ask for it")
    func restoresOnlyOnce() async {
        let access = StubFolderAccess(folder: .fixture())
        let app = makeAppViewModel(
            bookmarks: InMemoryBookmarkStore(bookmark: Data([0x11])),
            folderAccess: access
        )

        await FolderViewModel(app: app).start()
        await FolderViewModel(app: app).start()

        let restores = await access.restoredBookmarks
        #expect(restores.count == 1)
    }

    @Test("A window opened later starts fresh instead of reopening the remembered folder")
    func laterWindowStartsFresh() async {
        let app = makeAppViewModel(
            bookmarks: InMemoryBookmarkStore(bookmark: Data([0x11])),
            folderAccess: StubFolderAccess(folder: .fixture())
        )

        // The launch window takes the remembered folder...
        let launchWindow = FolderViewModel(app: app)
        await launchWindow.start()
        #expect(launchWindow.phase != .welcome(notice: nil))

        // ...and File ▸ New Window does not get a copy of it.
        let newWindow = FolderViewModel(app: app)
        #expect(newWindow.phase == .welcome(notice: nil), "A second window must not wait on an already-claimed launch")
        await newWindow.start()
        #expect(newWindow.phase == .welcome(notice: nil))
    }

    @Test("Two windows can hold two different folders at once")
    func windowsAreIndependent() async {
        let first = AuthorizedFolder.fixture(name: "Holidays")
        let second = AuthorizedFolder.fixture(name: "Wedding")
        let app = makeAppViewModel(folderAccess: StubFolderAccess(folder: first))

        let windowA = FolderViewModel(app: app)
        await windowA.handleSelection(.success([first.url]))
        let windowB = FolderViewModel(app: app)
        await windowB.handleSelection(.success([second.url]))

        #expect(windowA.phase == .editing(first))
        #expect(windowB.phase == .editing(second))
    }
}
