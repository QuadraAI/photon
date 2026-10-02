//
//  EditorToolbar.swift
//  Photon
//

import SwiftUI

/// The editor's toolbar: the sidebar toggle on the leading edge, undo and redo
/// trailing, and the selected photo's name in the middle.
///
/// Real `ToolbarContent` rather than a row of views, so macOS owns the bar — its
/// height, its spacing, and where the traffic lights sit inside it. That is what
/// lets the bar be tall enough for the controls to breathe while the lights stay
/// level with them; a hand-rolled row below a hidden title bar cannot do both,
/// because the lights stay pinned to the strip they were born in.
struct EditorToolbar: ToolbarContent {
    @Environment(EditorViewModel.self) private var editor

    /// Shown when nothing is selected, so the bar is never blank.
    let folderName: String

    /// How far the media sidebar pushes the bar's items right, in points, and
    /// zero while the sidebar is hidden. Only the title reads it; see ``title``.
    let sidebarOffset: CGFloat

    var body: some ToolbarContent {
        // Each control is its own item: the toolbar gives every item one chrome,
        // so bundling them would put all three inside a single capsule.
        //
        // No glass drawn here either — macOS 26 already supplies it, and adding
        // a second produced two chromes per control, one that followed the
        // content and one the toolbar owned.
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                undoButton
                redoButton
            }
            .controlGroupStyle(.navigation)
        }

        // Leading like the rest, and for the same reason: `.navigation` is the
        // placement the split view tracks, so this moves with the sidebar the
        // way undo and redo do. Trailing, it sat at the window's trailing edge —
        // which is where the tool rail is — so it landed *on* the rail with its
        // capsule crossing the rail's left edge. Nothing can hold a trailing
        // item clear of a trailing pane: they occupy the same strip by
        // definition, and tracking would only pull it further inside the rail.
        ToolbarItem(placement: .navigation) {
            // Deliberately no `menuStyle`: `borderlessButton` makes SwiftUI draw
            // the menu in-view, which both stacks a second chrome on the
            // toolbar's and drops the dropdown on top of the button. The default
            // lets macOS treat it as a toolbar item menu, placed below like the
            // popups in Xcode's own toolbar.
            //
            // No padding either. The item carries two chromes — the toolbar's and
            // the menu's own — and they only read as one control while they sit
            // concentrically. Padding pushed the outer one out, which showed as a
            // bigger shell around a smaller button that still had the smaller
            // button's hit area: padding outside a control grows the layout, not
            // the touch target.
            SettingsMenu()
                .font(.title2)
        }

        ToolbarItem(placement: .principal) {
            title
        }
        // The title brings its own glass, and the padding inside `title` is
        // layout the user should never see: without this the toolbar draws a
        // background around the padded item too, leaving an empty bubble hanging
        // off the capsule's trailing end.
        .sharedBackgroundVisibility(.hidden)
    }

    /// The selected photo's name, in a capsule the width of a MacBook's camera
    /// housing.
    ///
    /// macOS centres the item in the space the sidebar *leaves* it — half a
    /// sidebar right of the window's centre — while the housing this capsule
    /// stands in for belongs on the centre line. The trailing padding is what
    /// pulls it back: the padded item is a sidebar wider, and centring the wider
    /// item puts the capsule half of that width back to the left.
    ///
    /// Padding rather than an `offset`, which measurement showed drawn outside
    /// the item's frame — and clipped away to a fragment of itself.
    ///
    /// Corrected on macOS only: that is where the behaviour was measured, and the
    /// shift is far too large to apply blind to a platform whose toolbar may
    /// already centre its items on the window.
    @ViewBuilder private var title: some View {
        let capsule = Text(editor.selection?.name ?? folderName)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: AppLayout.toolbarTitleWidth)
            .frame(minHeight: AppLayout.toolbarTitleHeight)
            .glassEffect(.regular, in: .capsule)
            // On the capsule rather than on the padded view: the element the
            // window centres on — the one VoiceOver reads and the UI tests
            // measure — is the capsule, not the layout that moves it.
            .accessibilityIdentifier("editor.toolbar.title")

        #if os(macOS)
        capsule.padding(.trailing, sidebarOffset)
        #else
        capsule
        #endif
    }

    private var undoButton: some View {
        Button { editor.undo() } label: {
            Label { undoTitle } icon: { Image(systemName: "arrow.uturn.backward") }
                .labelStyle(.iconOnly)
                .font(.title2)
        }
        .disabled(!editor.canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .help(undoTitle)
        .accessibilityLabel(undoTitle)
        .accessibilityIdentifier("editor.toolbar.undo")
    }

    private var redoButton: some View {
        Button { editor.redo() } label: {
            Label { redoTitle } icon: { Image(systemName: "arrow.uturn.forward") }
                .labelStyle(.iconOnly)
                .font(.title2)
        }
        .disabled(!editor.canRedo)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .help(redoTitle)
        .accessibilityLabel(redoTitle)
        .accessibilityIdentifier("editor.toolbar.redo")
    }

    /// What undoing would take back, by name: "Undo Crop 16:9".
    ///
    /// Naming the step is the only part of a History panel that fits in a
    /// toolbar, and it is the part that matters most — the button says what it is
    /// about to do before it is pressed, which is what a plain "Undo" cannot.
    ///
    /// A `Text` rather than a `String`: the name is looked up when it is drawn,
    /// so it follows the app's language rather than the one that was on when the
    /// step was recorded.
    private var undoTitle: Text {
        editor.undoName?.undoTitle ?? Text("editor.undo")
    }

    private var redoTitle: Text {
        editor.redoName?.redoTitle ?? Text("editor.redo")
    }
}
