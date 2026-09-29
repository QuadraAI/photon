//
//  EditorUITestCase.swift
//  PhotonUITests
//

import XCTest

/// Base class for the editor's UI tests.
///
/// Every test starts the same way: launch the app and open the bundled fixture
/// folder through the *real* system picker. Photon is sandboxed with only
/// user-selected file access, so a path handed to it by any other route would be
/// denied — going through the panel is what makes this work with no test hooks
/// in the app.
///
/// XCTest rather than Swift Testing, because XCUITest has no Swift Testing
/// support.
///
/// `nonisolated` because `XCTestCase`'s initialisers and lifecycle hooks are,
/// and overriding them from a main-actor class is rejected outright. Everything
/// that touches the UI is marked `@MainActor` instead — every `XCUIElement`
/// access is main-actor isolated in Xcode 27.
///
/// `@unchecked Sendable` because a test case is driven by one thread for its
/// whole life, so `setUp` hopping to the main actor cannot race anything. It is
/// what lets `setUp` call the main-actor helpers below.
nonisolated class EditorUITestCase: XCTestCase, @unchecked Sendable {
    private(set) var app: XCUIApplication!

    /// `Tests/Photos` in the repository — the photo fixture the tests browse to.
    ///
    /// Deliberately a plain folder on disk rather than a resource in this bundle.
    /// The open panel treats an app or test bundle as a single file and will not
    /// navigate into one, so a bundled copy is unreachable however it is
    /// addressed.
    ///
    /// Derived from `#filePath`, which is this file's location at compile time —
    /// `Tests/UI/Support/EditorUITestCase.swift`, so three components up is
    /// `Tests`.
    static var fixtureFolder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Photos")
    }

    /// Every photo in the fixture: two in the root, two in `Subfolder`.
    static let allPhotoNames = ["alpha.png", "beta.png", "delta.jpg", "gamma.png"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: Self.fixtureFolder.path(percentEncoded: false)),
            "The photo fixture is missing from \(Self.fixtureFolder.path(percentEncoded: false))"
        )

        // XCTest runs the synchronous `setUp` on the main thread — which is what
        // lets `XCUIElement` work at all here — so asserting it is honest rather
        // than hopeful. The asynchronous variant gives no such guarantee.
        MainActor.assumeIsolated {
            app = XCUIApplication()
            app.launchArguments += [
                // The open panel belongs to the system, so its controls follow
                // the system language.
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                // The app's *own* language preference outranks the bundle lookup
                // above, and it lives in the real defaults — so a stored French
                // choice would leave these tests reading French labels. The
                // argument domain outranks the stored value without overwriting
                // it, which also keeps a test run from changing the developer's
                // settings.
                "-preferences.language", "en",
                "-preferences.theme", "light",
            ]
            app.launch()
            openFixtureFolder()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            app?.terminate()
            app = nil
        }
        super.tearDown()
    }

    // MARK: - Opening the fixture

    /// Drives the real open panel to the fixture folder.
    ///
    /// ⌘O rather than the welcome screen's button: Photon remembers the last
    /// folder, so a run may start either on the welcome screen or already in the
    /// editor, and File ▸ Open Folder… is reachable from both.
    @MainActor
    private func openFixtureFolder() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "Photon never opened a window")

        app.typeKey("o", modifierFlags: .command)

        // A sandboxed app's panel is hosted by a system service, but XCUITest
        // still exposes it inside the app's own tree, as `open-panel`.
        let panel = app.sheets["open-panel"]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 30),
            "The open panel never appeared.\n\(app.debugDescription)"
        )

        // ⌘⇧G opens the panel's "Go to Folder" sheet, which is the only reliable
        // way to reach a path without walking the browser by hand.
        panel.typeKey("g", modifierFlags: [.command, .shift])

        let goTo = app.sheets["GoToWindow"]
        XCTAssertTrue(goTo.waitForExistence(timeout: 30), "Go to Folder never appeared")

        let field = goTo.textFields.firstMatch
        field.typeText(Self.fixtureFolder.path(percentEncoded: false))
        // Return commits the sheet. Clicking its button does not: the sheet also
        // carries a completion table, so the first button found is not "Go".
        field.typeKey(.return, modifierFlags: [])

        // The panel treats an app or test bundle as a single file, which is why
        // the fixture lives at a plain path. With only folders choosable, the
        // folder it is *showing* is the selection, so this enables once the sheet
        // has closed and the navigation has landed — no separate wait needed.
        let confirm = panel.buttons["OKButton"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: confirm
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [ready], timeout: 30),
            .completed,
            "The panel never navigated to the fixture folder"
        )
        confirm.click()

        // Waiting on a fixture row rather than the toolbar title: the title is
        // already on screen when the app restored a previously remembered
        // folder, so it would pass before this folder had loaded.
        XCTAssertTrue(
            row(Self.allPhotoNames[0]).waitForExistence(timeout: 30),
            "The editor never listed the fixture folder"
        )
    }

    // MARK: - Waiting

    @MainActor
    func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 30) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == %@", NSNumber(value: false)),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func waitForToolbarTitle(_ expected: String) -> Bool {
        waitForValue(expected, of: "editor.toolbar.title")
    }

    @MainActor
    func waitForPanelTitle(_ expected: String) -> Bool {
        waitForValue(expected, of: "editor.toolPanel.title")
    }

    @MainActor
    private func waitForValue(_ expected: String, of identifier: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: app.staticTexts[identifier]
        )
        return XCTWaiter().wait(for: [expectation], timeout: 30) == .completed
    }

    // MARK: - Queries

    /// Every photo row currently in the sidebar.
    ///
    /// Matched on identifier against *any* element type: these are `List` rows,
    /// which XCUITest does not expose as buttons.
    @MainActor
    var sidebarRows: XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.sidebar.row."))
    }

    @MainActor
    func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["editor.sidebar.row.\(name)"]
    }

    /// A folder's row in the sidebar's tree.
    @MainActor
    func folderRow(_ path: String) -> XCUIElement {
        app.descendants(matching: .any)["editor.sidebar.folder.\(path)"]
    }

    /// The sidebar's filter field.
    @MainActor
    var sidebarFilter: XCUIElement {
        app.textFields["editor.sidebar.filter"]
    }

    /// The window's own sidebar toggle.
    ///
    /// The editor no longer draws this itself: a `.navigation` toolbar item is
    /// one the split view tracks, so it slid out over the canvas instead of
    /// staying over the sidebar. The system's toggle does stay put, and it has
    /// no identifier of ours to look up — its label flips with the sidebar's
    /// state, so both are tried. The suite pins the language to English, which
    /// is what makes those labels stable.
    @MainActor
    func sidebarToggle() -> XCUIElement {
        let hide = app.buttons["Hide Sidebar"]
        return hide.exists ? hide : app.buttons["Show Sidebar"]
    }

    /// The photo count in the sidebar header.
    @MainActor
    var sidebarCount: String? {
        text("editor.sidebar.count")
    }

    /// The text an identified element is showing, or nil when it is not on
    /// screen.
    ///
    /// Reads `value` first — SwiftUI puts a bare `Text` there — and falls back to
    /// `label`, which is where a composed element such as a section header keeps
    /// it. Reading either for an element that does not exist fails the test
    /// rather than returning nil, hence the existence check.
    @MainActor
    func text(_ identifier: String) -> String? {
        let element = app.descendants(matching: .any)[identifier]
        guard element.exists else { return nil }

        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label.isEmpty ? nil : element.label
    }

    @MainActor
    var toolbarTitle: String? {
        text("editor.toolbar.title")
    }

    /// Where the title capsule sits, in window coordinates.
    ///
    /// A frame rather than the text: the capsule and its glass are the thing the
    /// title's centring is about, and reading its edges is what catches the item
    /// being laid out off-centre rather than merely drawn at the wrong width.
    @MainActor
    var toolbarTitleFrame: CGRect {
        app.descendants(matching: .any)["editor.toolbar.title"].frame
    }

    @MainActor
    var toolPanelTitle: String? {
        text("editor.toolPanel.title")
    }

    @MainActor
    func tool(_ name: String) -> XCUIElement {
        app.buttons["editor.tools.\(name)"]
    }
}
