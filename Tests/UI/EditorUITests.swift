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
#if os(macOS)
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

        for name in ["crop", "light", "color", "presets"] {
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

    /// Cropping: the shape on the canvas changes, the toolbar offers to take it
    /// back *by name*, and ⌘Z puts it back.
    ///
    /// One test rather than three, because every launch pays for driving the real
    /// open panel and that costs more than any assertion here does.
    @MainActor
    func testCroppingChangesTheShapeAndUndoTakesItBack() {
        row("alpha.png").click()
        XCTAssertTrue(
            app.images["editor.canvas.image"].waitForExistence(timeout: 30),
            "The photo never reached the canvas"
        )
        XCTAssertEqual(canvasAspectRatio, 4.0 / 3.0, accuracy: 0.02, "alpha.png is 64×48")

        tool("crop").click()
        XCTAssertTrue(waitForPanelTitle("Crop & Rotate"), "The crop tool did not open its panel")

        app.buttons["tool.crop.ratio.1x1"].click()
        app.buttons["tool.crop.done"].click()

        XCTAssertTrue(
            waitForCanvasAspectRatio(1),
            "The canvas is at \(canvasAspectRatio) after cropping to a square"
        )

        let undo = app.buttons["editor.toolbar.undo"]
        XCTAssertTrue(undo.isEnabled, "Undo is disabled after committing a crop")
        XCTAssertTrue(
            undo.label.contains("1:1"),
            "The undo button reads \"\(undo.label)\", which does not name the step it would take back"
        )

        // Through the menu-bar shortcut rather than the button, so the Edit menu
        // and the toolbar are shown to be reading the same history.
        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(
            waitForCanvasAspectRatio(4.0 / 3.0),
            "Undo left the canvas at \(canvasAspectRatio)"
        )
        XCTAssertFalse(undo.isEnabled, "The only step was taken back, so there is nothing left to undo")
    }

    /// The colour tool: the panel offers the bands, a slider moves the value the
    /// panel reports, and ⌘Z takes the change away again.
    ///
    /// The sliders are drawn rather than borrowed, so this is also what holds the
    /// hand-built control to being a control: it is one element of the right kind
    /// — `app.sliders` finds it, which is what VoiceOver adjusts — it reports the
    /// number the panel draws beside it, and a click along its track lands the
    /// value where it was clicked rather than somewhere of its own choosing.
    ///
    /// A click rather than a drag, and deliberately. A click is the same gesture
    /// the pointer makes — the control's gesture begins on mouse-down, so a click
    /// is a drag of no distance — where a synthesized long press followed by a
    /// drag does not reach it, and `adjust(toNormalizedSliderPosition:)` cannot
    /// drive a SwiftUI slider on macOS at all: it asks for an orientation
    /// attribute the framework does not publish.
    @MainActor
    func testTheColourPanelReportsTheGradeItMade() {
        row("alpha.png").click()
        XCTAssertTrue(
            app.images["editor.canvas.image"].waitForExistence(timeout: 30),
            "The photo never reached the canvas"
        )

        tool("color").click()
        XCTAssertTrue(waitForPanelTitle("Color"), "The colour tool did not open its panel")

        // The eight bands, in the mode the panel opens on. A slider reports the
        // number the panel draws beside it, which for these is whole percents.
        let yellow = app.sliders["tool.color.band.yellow.saturation"]
        XCTAssertTrue(yellow.waitForExistence(timeout: 10), "The yellow band has no slider")
        XCTAssertEqual(number(yellow), 0, "A photo nothing has been done to reads as neutral")

        // Four fifths of the way along the control. The thumb travels within its
        // own width, so that is a shade past four fifths of the range.
        yellow.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).click()

        let clicked = number(yellow)
        XCTAssertEqual(
            clicked,
            64,
            accuracy: 6,
            "Clicking four fifths along the yellow track landed it at \(clicked)"
        )

        // And the arrow keys move it, which is what the control takes focus for
        // — the path Full Keyboard Access and Switch Control need.
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])

        XCTAssertEqual(
            number(yellow),
            clicked + 2,
            accuracy: 2,
            "Two arrow keys moved the slider from \(clicked) to \(number(yellow))"
        )

        let undo = app.buttons["editor.toolbar.undo"]
        XCTAssertTrue(undo.isEnabled, "Undo is disabled after a colour change")
        XCTAssertTrue(
            undo.label.contains("Saturation"),
            "The undo button reads \"\(undo.label)\", which does not name the slider that moved"
        )

        app.typeKey("z", modifierFlags: .command)

        XCTAssertEqual(number(yellow), 0, "Undo left the slider where it was")
        XCTAssertFalse(undo.isEnabled, "The only step was taken back, so there is nothing left to undo")
    }

    /// What a slider is set to, as a number.
    ///
    /// A number rather than a string: it is what a slider's accessibility value
    /// is, and it is the figure the panel draws beside the track.
    @MainActor
    private func number(_ element: XCUIElement) -> Double {
        (element.value as? NSNumber)?.doubleValue ?? .nan
    }

    /// The mode picker moves the same eight bands from one of the three things
    /// they can change to another.
    @MainActor
    func testTheColourPanelSwitchesModes() {
        row("alpha.png").click()
        XCTAssertTrue(app.images["editor.canvas.image"].waitForExistence(timeout: 30))

        tool("color").click()
        XCTAssertTrue(waitForPanelTitle("Color"))

        let saturation = app.sliders["tool.color.band.yellow.saturation"]
        XCTAssertTrue(saturation.waitForExistence(timeout: 10), "The panel does not open on saturation")

        let picker = app.menuButtons["tool.color.channel"]
        XCTAssertTrue(picker.exists, "The panel offers no mode picker")
        XCTAssertEqual(picker.value as? String, "Saturation", "The picker does not say which mode it is on")

        picker.click()
        app.menuItems["Hue"].click()

        XCTAssertTrue(
            app.sliders["tool.color.band.yellow.hue"].waitForExistence(timeout: 10),
            "Switching to hue did not hand the band rows over to it"
        )
        XCTAssertFalse(saturation.exists, "The rows are still the saturation ones")
        XCTAssertEqual(picker.value as? String, "Hue", "The picker still says it is on saturation")
    }

    /// The crop is operable, and readable, without a pointer.
    ///
    /// The overlay is eight drag targets, which VoiceOver, Switch Control and
    /// Voice Control cannot use — so the panel has to carry every crop it can
    /// make, and each control has to report what it currently is. This checks the
    /// second half against a crop the first half made.
    @MainActor
    func testTheCropPanelReportsTheCropItMade() {
        row("alpha.png").click()
        XCTAssertTrue(app.images["editor.canvas.image"].waitForExistence(timeout: 30))

        tool("crop").click()
        XCTAssertTrue(waitForPanelTitle("Crop & Rotate"))

        // Nothing has been taken off any edge yet.
        let rightEdge = app.descendants(matching: .any)["tool.crop.edge.right"]
        XCTAssertTrue(rightEdge.waitForExistence(timeout: 10), "The right edge has no control")
        XCTAssertEqual(rightEdge.value as? String, "0%", "The whole photo is in the crop")

        // 4:5 out of a 4:3 photo takes a fifth off each side — a whole number of
        // per cent, so the readout below is not asserting which way a half rounds.
        app.buttons["tool.crop.ratio.4x5"].click()

        XCTAssertTrue(
            waitForCanvasAspectRatio(4.0 / 5.0),
            "Picking a portrait shape did not reshape the crop"
        )
        XCTAssertEqual(
            rightEdge.value as? String,
            "20%",
            "The right edge does not report the crop that was made"
        )

        // And the ratio that is on says so, rather than only being tinted.
        XCTAssertTrue(
            app.buttons["tool.crop.ratio.4x5"].isSelected,
            "The chosen ratio is not marked as selected"
        )
    }

    /// Dragging the crop by its inside moves it, and lands it near where the
    /// finger went.
    ///
    /// A regression test for a drag that fed itself. The gesture was measured in
    /// the crop's own coordinate space, so moving the crop moved the ruler it was
    /// being measured against and the two chased each other at frame rate — the
    /// crop twitching between two places rather than following the pointer. A
    /// drag that overshoots or lurches shows up here as an inset well outside the
    /// band the finger asked for.
    @MainActor
    func testDraggingTheCropInsideMovesItWhereTheFingerWent() {
        row("alpha.png").click()
        XCTAssertTrue(app.images["editor.canvas.image"].waitForExistence(timeout: 30))

        tool("crop").click()
        XCTAssertTrue(waitForPanelTitle("Crop & Rotate"))

        // A square out of a 4:3 photo sits an eighth in from each side, which
        // leaves room to drag it sideways and something to measure against.
        app.buttons["tool.crop.ratio.1x1"].click()
        XCTAssertTrue(waitForCanvasAspectRatio(1), "Picking a square did not reshape the crop")

        let leftEdge = app.descendants(matching: .any)["tool.crop.edge.left"]
        XCTAssertTrue(leftEdge.waitForExistence(timeout: 10))
        XCTAssertEqual(leftEdge.value as? String, "13%", "A square sits an eighth in")

        let image = app.images["editor.canvas.image"]
        let start = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // A tenth of the picture to the right: less than the eighth of room the
        // square has before it runs into the edge, so the crop can actually go
        // the whole way and nothing but the drag decides where it stops.
        let end = start.withOffset(CGVector(dx: image.frame.width * 0.1, dy: 0))

        start.press(forDuration: 0.2, thenDragTo: end)

        // An eighth plus a tenth is 22.5%, and the band around it is wide enough
        // for the pixels a synthesized drag loses at each end — but nowhere near
        // wide enough to pass a crop that ran away, which is the failure this
        // exists for.
        let landed = Double((leftEdge.value as? String ?? "").replacingOccurrences(of: "%", with: "")) ?? -1
        XCTAssertEqual(
            landed,
            23,
            accuracy: 6,
            "Dragging the crop a tenth of the picture right landed it at \(landed)%"
        )
    }
}
#endif

#if os(iOS)
/// The iPad's way in: the welcome screen, the system file picker its button
/// presents, and the editor the folder it remembers opens into.
///
/// Not `EditorUITests`: that drives a menu bar and an open panel iPadOS has no
/// equivalent of, and can steer its panel by path.
nonisolated final class WelcomeUITests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!

    /// The folder Photon remembers, as the flag the store reads.
    ///
    /// Overriding it with something that is not bookmark data is how a test gets
    /// the welcome screen on a simulator that has already been given a folder.
    private static let rememberedFolder = "-folder.rememberedBookmark"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            app?.terminate()
            app = nil
        }
        super.tearDown()
    }

    /// Launches Photon, optionally with nothing remembered.
    @MainActor
    private func launch(forgettingFolders forgotten: Bool) {
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            // The app's own preference outranks the bundle lookup above, and it
            // lives in the real defaults.
            "-preferences.language", "en",
            "-preferences.theme", "light",
        ]
        if forgotten {
            app.launchArguments += [Self.rememberedFolder, ""]
        }
        app.launch()
    }

    @MainActor
    func testWelcomeScreenPresentsTheSystemFilePicker() {
        launch(forgettingFolders: true)

        let chooseFolder = app.buttons["welcome.chooseFolder"]
        XCTAssertTrue(
            chooseFolder.waitForExistence(timeout: 30),
            "Photon never showed the welcome screen:\n\(app.debugDescription)"
        )
        XCTAssertTrue(app.buttons["Language"].exists, "The language menu is missing from the welcome screen")
        XCTAssertTrue(app.buttons["Appearance"].exists, "The appearance menu is missing from the welcome screen")

        chooseFolder.tap()

        // The picker is a system view service drawn over the app, not a view
        // inside it: XCUITest cannot reach its contents, so the sign that it
        // arrived is the button it was pressed on being covered.
        let covered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == false"),
            object: chooseFolder
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [covered], timeout: 30),
            .completed,
            "The system file picker never came up over the welcome screen"
        )
    }

    /// The editor, reached the way a user reaches it on a second launch: Photon
    /// reopening the folder it was last given.
    ///
    /// The folder has to hold the photo fixture, and a test cannot put it there
    /// — the picker's contents are out of XCUITest's reach, and the app's own
    /// container is not a Files location. Seeding it is a one-off, done outside
    /// the app; without it this test skips rather than fails, so a fresh
    /// simulator does not report a lie.
    @MainActor
    func testTheRememberedFolderOpensTheEditor() throws {
        launch(forgettingFolders: false)

        guard app.buttons["editor.canvas.openFolder"].waitForExistence(timeout: 30) else {
            throw XCTSkip(
                "No folder is remembered on this simulator. Open one through the picker once, "
                    + "or seed it: copy Tests/Photos into the device's "
                    + "\"File Provider Storage\" for com.apple.FileProvider.LocalStorage."
            )
        }

        guard app.photoRow("alpha.png").waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "The remembered folder holds no fixture photos. Copy Tests/Photos into the "
                    + "device's \"File Provider Storage\" for com.apple.FileProvider.LocalStorage."
            )
        }

        XCTAssertTrue(app.photoRow("beta.png").exists, "The root's second photo is missing")
        XCTAssertFalse(app.photoRow("notes.txt").exists, "A text file is not a photo")
        XCTAssertFalse(app.photoRow(".hidden.png").exists, "Hidden files are skipped")

        // The tree: a folder's photos are listed when it is opened.
        let subfolder = app.folderRow("Subfolder")
        XCTAssertTrue(subfolder.exists, "The subfolder is missing from the tree:\n\(app.debugDescription)")
        subfolder.tap()
        XCTAssertTrue(app.photoRow("delta.jpg").waitForExistence(timeout: 20), "The nested photo never appeared")
        XCTAssertTrue(app.photoRow("gamma.png").exists, "The folder's other photo is missing")

        // And choosing one puts it on the canvas.
        app.photoRow("alpha.png").tap()
        XCTAssertTrue(
            app.images["editor.canvas.image"].waitForExistence(timeout: 30),
            "The photo never reached the canvas on iPadOS"
        )
    }
}
#endif
