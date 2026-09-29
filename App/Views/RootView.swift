//
//  RootView.swift
//  Photon
//

import SwiftUI
import UniformTypeIdentifiers

/// One window's root: routes between the screens and owns the pieces that
/// outlive any one of them — the folder picker, the failure alert, and the
/// decision about which folder this window is working in.
///
/// The folder state is `@State` here rather than on ``PhotonApp`` on purpose. A
/// window's folder is not app state: File ▸ New Window has to start fresh, and
/// picking a folder in one window must not move any other.
struct RootView: View {
    private let app: AppViewModel
    @State private var folder: FolderViewModel
    @State private var editor: EditorViewModel

    init(app: AppViewModel) {
        self.app = app
        _folder = State(initialValue: FolderViewModel(app: app))
        _editor = State(
            initialValue: EditorViewModel(
                library: FileSystemPhotoLibrary(),
                renderer: ImageIOPhotoRenderer()
            )
        )
    }

    var body: some View {
        content
            .environment(app)
            .environment(folder)
            .environment(editor)
            .appPresentation(app.preferences)
            // Lets the menu bar act on *this* window's folder and editor.
            .focusedSceneValue(folder)
            .focusedSceneValue(editor)
            .fileImporter(
                isPresented: $folder.isChoosingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                Task { await folder.handleSelection(result) }
            }
            .alert(
                "error.alert.title",
                isPresented: $folder.isShowingFailure,
                presenting: folder.failure
            ) { _ in
                Button("action.ok") { folder.isShowingFailure = false }
            } message: { failure in
                Text(failure.message)
            }
            .task { await folder.start() }
    }

    @ViewBuilder private var content: some View {
        switch folder.phase {
        case .starting:
            launchPlaceholder
        case .welcome(let notice):
            WelcomeView(notice: notice)
        case .editing(let openFolder):
            EditorView(folder: openFolder)
        }
    }

    /// Shown only while the remembered folder is being resolved.
    ///
    /// Deliberately echoes the welcome screen's header so a fast resolve reads
    /// as continuity rather than as a flash of the wrong screen.
    private var launchPlaceholder: some View {
        VStack(spacing: 12) {
            AppMark()

            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("launch.restoring")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
