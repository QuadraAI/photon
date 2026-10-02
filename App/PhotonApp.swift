//
//  PhotonApp.swift
//  Photon
//

import SwiftUI

@main
struct PhotonApp: App {
    /// App-scoped: settings, services, and the once-per-launch folder restore.
    /// Each window owns its own ``FolderViewModel`` and ``EditorViewModel``
    /// inside ``RootView``.
    @State private var app: AppViewModel

    /// The editing engine, one for the whole app.
    ///
    /// A `CIContext` caches compiled kernels and intermediate buffers, so a
    /// second one costs a second compile and gives nothing back — which is why
    /// this is built in the composition root and handed to every window rather
    /// than made inside each one.
    private let engine: PhotoEditing

    init() {
        // Composition root: the only place concrete services are built. Every
        // other type receives its dependencies through an initializer.
        let defaults = UserDefaults.standard
        engine = CoreImagePhotoEditor()
        _app = State(
            initialValue: AppViewModel(
                preferencesStore: UserDefaultsPreferencesStore(defaults: defaults),
                bookmarkStore: UserDefaultsBookmarkStore(defaults: defaults),
                folderAccess: SecurityScopedFolderAccess()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app, engine: engine)
        }
        .defaultSize(AppLayout.windowSize)
        // macOS-only: SwiftUI has no window toolbar style on iPadOS. `unified`
        // is what centres the traffic lights in the toolbar's height, so a taller
        // bar takes them with it instead of leaving them behind.
        #if os(macOS)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            FolderCommands()
            EditorCommands()
        }
    }
}

/// Menu bar commands that act on the folder of the window in focus.
///
/// The command has no window of its own, so it reads the focused window's model
/// through `FocusedValue` rather than reaching for a shared instance — which is
/// what keeps File ▸ Open Folder… acting on the window the user is looking at
/// instead of whichever one happens to be first.
struct FolderCommands: Commands {
    @FocusedValue(FolderViewModel.self) private var folder: FolderViewModel?

    var body: some Commands {
        // Serves both platforms: macOS puts this in the File menu, iPadOS
        // surfaces it in the menu bar, and ⌘O works with a keyboard on either.
        CommandGroup(after: .newItem) {
            Button("command.openFolder") { folder?.chooseFolder() }
                .keyboardShortcut("o")
                .disabled(folder == nil)
        }
    }
}

/// Undo and redo for the focused window's selected photo.
///
/// Replaces the standard Edit ▸ Undo group so the menu items read from the same
/// history the toolbar's buttons do — including the name of the step, so the
/// menu says "Undo Crop 16:9" rather than "Undo" — and can be disabled when
/// there is nothing to take back.
struct EditorCommands: Commands {
    @FocusedValue(EditorViewModel.self) private var editor: EditorViewModel?

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button {
                editor?.undo()
            } label: {
                editor?.undoName?.undoTitle ?? Text("editor.undo")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(editor?.canUndo != true)

            Button {
                editor?.redo()
            } label: {
                editor?.redoName?.redoTitle ?? Text("editor.redo")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(editor?.canRedo != true)
        }
    }
}
