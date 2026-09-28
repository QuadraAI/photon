//
//  FolderViewModelTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// The window-scoped model: which folder this window is working in, and the
/// folder picker underneath it.
///
/// The picker is presented by `RootView`, but nothing about the outcome lives
/// there — the view forwards the picker's result to
/// ``FolderViewModel/handleSelection(_:)``, which makes the whole flow testable
/// without a UI.
@Suite("Window folder")
@MainActor
struct FolderViewModelTests {
    // MARK: - The picker

    @Test("The picker starts hidden")
    func startsHidden() {
        let window = makeWindow()

        #expect(window.folderPick == .idle)
        #expect(window.isChoosingFolder == false)
    }

    @Test("Choosing a folder presents the picker")
    func presentsPicker() {
        let window = makeWindow()

        window.chooseFolder()

        #expect(window.folderPick == .presenting)
        #expect(window.isChoosingFolder)
    }

    @Test("Dismissing the picker without a choice returns to idle")
    func dismissalReturnsToIdle() {
        let window = makeWindow()
        window.chooseFolder()

        window.isChoosingFolder = false

        #expect(window.folderPick == .idle)
    }

    @Test("A dismissal does not discard a failure the user has not seen yet")
    func dismissalKeepsPendingFailure() async {
        let window = makeWindow(failure: .accessDenied)
        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))

        window.isChoosingFolder = false

        #expect(window.failure == .accessDenied)
    }

    @Test("Cancelling the picker returns to idle without reporting a failure")
    func cancelledPickIsNotAFailure() async {
        let window = makeWindow()

        await window.handleSelection(.failure(CocoaError(.userCancelled)))

        #expect(window.folderPick == .idle)
        #expect(window.failure == nil)
        #expect(window.phase == .welcome(notice: nil))
    }

    @Test("An empty selection returns to idle without reporting a failure")
    func emptySelectionIsNotAFailure() async {
        let window = makeWindow()

        await window.handleSelection(.success([]))

        #expect(window.folderPick == .idle)
        #expect(window.failure == nil)
    }

    @Test("The picker is idle again once a folder has been opened")
    func returnsToIdleAfterOpening() async {
        let window = makeWindow()

        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))

        #expect(window.folderPick == .idle)
    }

    // MARK: - Opening

    @Test("A picked folder becomes the one this window works in")
    func opensPickedFolder() async {
        let window = makeWindow()

        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))

        #expect(window.phase == .editing(.fixture()))
        #expect(window.failure == nil)
    }

    @Test("A folder that cannot be opened is reported without changing the screen")
    func reportsFailureWithoutChangingPhase() async {
        let window = makeWindow(failure: .accessDenied)

        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))

        #expect(window.failure == .accessDenied)
        #expect(window.phase == .welcome(notice: nil))
    }

    @Test("A file picked instead of a folder is reported as such")
    func reportsNotADirectory() async {
        let window = makeWindow(failure: .notADirectory)

        await window.handleSelection(.success([URL(filePath: "/tmp/photo.jpg")]))

        #expect(window.failure == .notADirectory)
    }

    @Test("A failed switch keeps the folder that was already open")
    func failedSwitchKeepsCurrentFolder() async {
        let access = StubFolderAccess(folder: .fixture())
        let window = makeWindow(access: access)
        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))
        #expect(window.phase == .editing(.fixture()))

        await access.setFailure(.notADirectory)
        await window.handleSelection(.success([URL(filePath: "/tmp/photo.jpg")]))

        #expect(window.failure == .notADirectory)
        #expect(window.phase == .editing(.fixture()), "A failed switch must not close the working folder")
    }

    // MARK: - Dismissing a failure

    @Test("Dismissing the alert clears the failure")
    func dismissesFailure() async {
        let window = makeWindow(failure: .accessDenied)
        await window.handleSelection(.success([AuthorizedFolder.fixtureURL]))
        #expect(window.isShowingFailure)

        window.isShowingFailure = false

        #expect(window.failure == nil)
    }

    @Test("Dismissing when nothing failed leaves the window alone")
    func dismissIsHarmless() {
        let window = makeWindow()

        window.isShowingFailure = false

        #expect(window.phase == .welcome(notice: nil))
    }

    // MARK: - Helpers

    private func makeWindow(
        failure: FolderAccessError? = nil,
        access: StubFolderAccess? = nil
    ) -> FolderViewModel {
        FolderViewModel(
            app: makeAppViewModel(
                folderAccess: access ?? StubFolderAccess(folder: .fixture(), failure: failure)
            )
        )
    }
}
