//
//  EditorUITests.swift
//  PhotonUITests
//

import XCTest

/// End-to-end coverage of the editor.
///
/// Three tests, not one per control. Every test launches the app and drives the
/// real open panel, and that setup costs far more than any assertion does — so
/// the app is launched as few times as possible, and each launch is spent on a
/// whole flow.
nonisolated final class EditorUITests: EditorUITestCase, @unchecked Sendable {
    /// Opening a folder, everything the editor shows before a photo is picked,
    /// and the sidebar toggle.
    @MainActor
    func testOpeningAFolderShowsItsPhotosAndTheEditorChrome() {
        // The sidebar lists the folder's folders, so the nested photos appear
        // when their folder is opened.
        XCTAssertEqual(sidebarRows.count, 2, "The root's two photos are listed straight away")
        XCTAssertTrue(
            folderRow("Subfolder").exists,
            "The subfolder the fixture's nested photos are in is missing"
        )

        folderRow("Subfolder").click()

        XCTAssertEqual(
            sidebarRows.count,
            4,
            "Expected the four fixture photos — notes.txt and the dotfile must be ignored"
        )
        for name in Self.allPhotoNames {
            XCTAssertTrue(row(name).exists, "\(name) is missing from the sidebar")
        }
        XCTAssertFalse(row("notes.txt").exists, "A text file is not a photo")
        XCTAssertFalse(row(".hidden.png").exists, "Hidden files are skipped")

        XCTAssertEqual(toolbarTitle, Self.fixtureFolder.lastPathComponent)
        // The count sits in the section header, which SwiftUI exposes as one
        // composed element, so this checks it is reported rather than reading a
        // bare number.
        XCTAssertTrue(
            (sidebarCount ?? "").contains("4"),
            "The sidebar header should count the photos, got \(sidebarCount ?? "nothing")"
        )

        // Which folder a photo came from is the tree's job now, not a label on
        // every row: two subfolders can hold the same file name.
        XCTAssertTrue(
            (text("editor.sidebar.folder.Subfolder") ?? "").contains("Subfolder"),
            "The folder a nested photo came from should be listed, got \(text("editor.sidebar.folder.Subfolder") ?? "nothing")"
        )
        XCTAssertEqual(folderRow("Subfolder").isSelected, false, "A folder is not a photo")

        XCTAssertFalse(
            app.images["editor.canvas.image"].exists,
            "Nothing should be rendered until a photo is chosen"
        )
        XCTAssertTrue(
            app.buttons["editor.canvas.openFolder"].exists,
            "The empty canvas should offer to open a different folder"
        )
        // The placeholder stands in for a photo, and it is centred on the window
        // rather than on the canvas — the canvas is what the panes around it push
        // off the window's centre line, which is where the title capsule sits.
        XCTAssertEqual(
            app.buttons["editor.canvas.openFolder"].frame.midX,
            app.windows.firstMatch.frame.midX,
            accuracy: 2,
            "The empty canvas is not centred on the window"
        )

        for name in ["crop", "light", "color", "details", "presets"] {
            XCTAssertTrue(tool(name).exists, "The \(name) tool is missing from the rail")
        }
        XCTAssertNil(toolPanelTitle, "No tool panel should be open to begin with")
        XCTAssertFalse(
            app.buttons["editor.toolbar.undo"].isEnabled,
            "Undo must be disabled until the first edit lands"
        )
        XCTAssertFalse(
            app.buttons["editor.toolbar.redo"].isEnabled,
            "Redo must be disabled until something has been undone"
        )

        // The top bar must sit on the traffic lights' line. macOS reserves a
        // 32pt strip for the hidden title bar, and laying the bar out *below*
        // that strip is the bug this guards — so the comparison is against the
        // real window buttons rather than a number that could drift.
        let toggle = sidebarToggle()
        let windowButtons = app.windows.firstMatch.buttons
        let close = windowButtons["_XCUI:CloseWindow"]
        let zoom = windowButtons["_XCUI:FullScreenWindow"]
        XCTAssertTrue(close.exists, "Could not find the window's close button")
        XCTAssertTrue(zoom.exists, "Could not find the window's zoom button")
        XCTAssertEqual(
            toggle.frame.midY,
            close.frame.midY,
            accuracy: 1,
            "The top bar is not on the traffic lights' line"
        )
        XCTAssertGreaterThanOrEqual(
            toggle.frame.minX,
            zoom.frame.maxX,
            "The top bar's first control overlaps the window buttons"
        )

        // The sidebar is open here, which is the state that used to put the
        // title off-centre: macOS hands the toolbar only the space the sidebar
        // leaves it, and centres the title in that unless it is told otherwise.
        assertTitleIsCentred("with the media sidebar open")

        // The sidebar is a split-view column, so the toolbar can track its
        // divider: AppKit shifts items that follow a tracking separator, which
        // is how Xcode's and Mail's toolbar buttons move with their sidebars.
        // Undo is measured rather than the sidebar toggle, because the system's
        // toggle is deliberately *not* one of the tracked items — it stays put
        // over the sidebar, as Xcode's does.
        let openX = app.buttons["editor.toolbar.undo"].frame.minX

        sidebarToggle().click()
        XCTAssertTrue(
            waitForDisappearance(of: row("alpha.png")),
            "The media sidebar is still on screen after being hidden"
        )

        // Hiding the sidebar must not move the title either: it is the window's
        // centre line the capsule belongs on, not the canvas's.
        assertTitleIsCentred("with the media sidebar hidden")

        let closedX = app.buttons["editor.toolbar.undo"].frame.minX
        XCTAssertLessThan(
            closedX,
            openX,
            "The top bar did not follow the sidebar's divider: undo held at x=\(openX) with the sidebar open and x=\(closedX) with it closed"
        )

        sidebarToggle().click()
        XCTAssertTrue(
            row("alpha.png").waitForExistence(timeout: 10),
            "The media sidebar never came back"
        )

        // Filtering, last so it cannot disturb the assertions above.
        XCTAssertTrue(sidebarFilter.exists, "The sidebar should offer a filter field")
        sidebarFilter.click()
        sidebarFilter.typeText("beta")

        XCTAssertTrue(
            waitForDisappearance(of: row("alpha.png")),
            "Filtering did not narrow the list"
        )
        XCTAssertTrue(row("beta.png").exists, "The matching photo should still be listed")
        XCTAssertTrue(
            (sidebarCount ?? "").contains("1"),
            "The header count should follow the filter, got \(sidebarCount ?? "nothing")"
        )

        app.buttons["editor.sidebar.filter.clear"].click()
        XCTAssertTrue(
            row("alpha.png").waitForExistence(timeout: 10),
            "Clearing the filter did not restore the list"
        )
        XCTAssertTrue((sidebarCount ?? "").contains("4"), "The count should come back with the list")
    }

    /// The title capsule is modelled on a MacBook's camera housing, so it belongs
    /// on the window's centre line whatever the panes around it are doing — and
    /// macOS would otherwise place it half a sidebar to the right of that line
    /// whenever the sidebar is open.
    ///
    /// Two points of slack, which is what the window's own rounding is worth:
    /// the misplacement this guards against was more than a hundred.
    @MainActor
    private func assertTitleIsCentred(_ state: String) {
        XCTAssertEqual(
            toolbarTitleFrame.midX,
            app.windows.firstMatch.frame.midX,
            accuracy: 2,
            "The toolbar title is not centred on the window \(state)"
        )
    }

    /// Picking photos, including one nested two levels down.
    @MainActor
    func testChoosingPhotosRendersThemAndNamesThemInTheToolbar() {
        folderRow("Subfolder").click()

        row("alpha.png").click()
        XCTAssertTrue(
            app.images["editor.canvas.image"].waitForExistence(timeout: 30),
            "The photo never reached the canvas"
        )
        XCTAssertEqual(toolbarTitle, "alpha.png")

        row("beta.png").click()
        XCTAssertTrue(
            waitForToolbarTitle("beta.png"),
            "The toolbar still reads \(toolbarTitle ?? "nothing") after choosing beta.png"
        )
        XCTAssertEqual(app.images["editor.canvas.image"].label, "beta.png")

        row("delta.jpg").click()
        XCTAssertTrue(
            waitForToolbarTitle("delta.jpg"),
            "A photo in a subfolder did not reach the canvas"
        )
        XCTAssertEqual(app.images["editor.canvas.image"].label, "delta.jpg")
    }

    /// The rail opens a tool's panel, swaps it, and closes it again.
    @MainActor
    func testTheToolRailOpensSwapsAndClosesToolPanels() {
        XCTAssertNil(toolPanelTitle, "No panel should be open to begin with")

        tool("color").click()
        XCTAssertTrue(waitForPanelTitle("Color"), "Clicking the Colour tool did not open its panel")

        // The panel is a pane inside the detail column, so opening it must not
        // move what the toolbar centres on.
        assertTitleIsCentred("with a tool panel open")

        tool("light").click()
        XCTAssertTrue(
            waitForPanelTitle("Light"),
            "Choosing another tool should swap the panel, not close it"
        )

        tool("light").click()
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["editor.toolPanel.title"]),
            "Clicking the open tool again did not close its panel"
        )
    }
}
