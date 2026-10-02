//
//  Previews.swift
//  Photon
//

#if DEBUG
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// Preview fixtures.
///
/// Kept behind `#if DEBUG` so the throwaway defaults domain below can never be
/// compiled into a release build.
extension AppViewModel {
    /// A view model wired to a throwaway defaults domain, seeded with
    /// `preferences`, so previewing never touches the real app preferences.
    ///
    /// The empty bookmark store is what settles ``AppPhase`` onto the welcome
    /// screen, so no launch resolution is needed.
    static func preview(_ preferences: AppPreferences = AppPreferences()) -> AppViewModel {
        preview(preferences, variant: "welcome", bookmark: nil)
    }

    /// A view model whose stored bookmark cannot be resolved.
    ///
    /// Drives the real launch path rather than forcing the phase, which keeps
    /// the preview honest: if ``restoreRememberedFolder()`` ever stops producing
    /// the notice, this preview breaks with it.
    static func previewWithUnresolvableBookmark(
        _ preferences: AppPreferences = AppPreferences()
    ) -> AppViewModel {
        preview(preferences, variant: "broken-bookmark", bookmark: Data([0x00, 0x01, 0x02, 0x03]))
    }

    /// The defaults domain is keyed by everything that affects the outcome, so
    /// previews side by side cannot overwrite each other's state.
    private static func preview(
        _ preferences: AppPreferences,
        variant: String,
        bookmark: Data?
    ) -> AppViewModel {
        let suite = "com.quadra.Photon.preview.\(variant).\(preferences.language.rawValue).\(preferences.theme.rawValue)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard

        let preferencesStore = UserDefaultsPreferencesStore(defaults: defaults)
        preferencesStore.save(preferences)

        let bookmarkStore = UserDefaultsBookmarkStore(defaults: defaults)
        bookmarkStore.saveBookmark(bookmark)

        return AppViewModel(
            preferencesStore: preferencesStore,
            bookmarkStore: bookmarkStore,
            folderAccess: SecurityScopedFolderAccess()
        )
    }
}

/// The folder the editor previews pretend to have open.
private let previewFolder = AuthorizedFolder(
    url: URL(filePath: "/Users/Shared/Holiday Photos", directoryHint: .isDirectory),
    bookmark: nil
)

/// Stands in for the file system, so the editor preview shows a populated
/// sidebar without depending on the machine's own folders.
private struct PreviewPhotoLibrary: PhotoLibraryLoading {
    /// Two entries share a name in different subfolders on purpose — that is the
    /// case the sidebar's tooltip exists for.
    private static let entries: [(name: String, folder: String)] = [
        ("IMG_0001.heic", ""),
        ("IMG_0002.heic", ""),
        ("IMG_0003.jpg", ""),
        ("Sunset.jpg", ""),
        ("DSC_0042.NEF", ""),
        ("Portrait.jpg", "Backup"),
        ("IMG_0001.heic", "Backup"),
    ]

    func photos(in folder: URL) async throws(PhotoLibraryError) -> [PhotoItem] {
        Self.entries.map { entry in
            let name = entry.folder.isEmpty ? entry.name : "\(entry.folder)/\(entry.name)"
            let type = UTType(filenameExtension: URL(filePath: entry.name).pathExtension)
            return PhotoItem(
                url: folder.appending(path: name),
                subfolderPath: entry.folder,
                // Enough classification to keep the RAW glyph on the NEF above.
                isRAW: type?.conforms(to: .rawImage) == true
            )
        }
    }
}

/// Stands in for the editing engine: a flat swatch, which is enough to show the
/// canvas is laid out and scaling rather than stretched — and, because it reports
/// a real size and renders at the size asked for, enough for the crop overlay to
/// have a frame to sit on.
private struct PreviewPhotoEditor: PhotoEditing {
    /// A canvas draws its preview with the context that staged it; nothing here
    /// is drawn anywhere but a preview, so it is a context like any other.
    let context = CIContext()

    /// What the pretend photo is, in pixels. Reported to the crop maths and
    /// rendered at, so a preview of the crop tool shows a crop and not a
    /// contradiction.
    private static let size = CGSize(width: 1200, height: 800)

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        try swatch()
    }

    func preview(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CIImage {
        CIImage(cgImage: try swatch())
    }

    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage {
        try swatch()
    }

    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize {
        Self.size
    }

    private func swatch() throws(PhotoRenderError) -> CGImage {
        let size = Self.size
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw .unreadable }

        context.setFillColor(CGColor(red: 0.16, green: 0.34, blue: 0.60, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0.35, green: 0.62, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: size.width * 0.25, y: size.height * 0.25, width: size.width * 0.5, height: size.height * 0.5))

        guard let image = context.makeImage() else { throw .unreadable }
        return image
    }
}

/// A whole window, at the size the app actually opens at.
private func previewWindow(_ app: AppViewModel) -> some View {
    RootView(app: app, engine: PreviewPhotoEditor()).previewFramed()
}

/// A single screen, wired the way `RootView` wires it.
///
/// `RootView` resolves the launch asynchronously, so building a screen directly
/// is the only way to preview a settled state deterministically. Framing is left
/// to the call site, because the welcome screen and the editor are different
/// sizes.
private func previewScreen(
    _ content: some View,
    app: AppViewModel,
    editor: EditorViewModel? = nil
) -> some View {
    content
        .environment(app)
        .environment(FolderViewModel(app: app))
        .environment(editor ?? previewEditor(app))
        .appPresentation(app.preferences)
}

private func previewEditor(_ app: AppViewModel) -> EditorViewModel {
    EditorViewModel(library: PreviewPhotoLibrary(), renderer: PreviewPhotoEditor())
}

private extension View {
    /// Pins a preview to the app's window size.
    ///
    /// Left to itself the canvas picks its own size, which hides how the
    /// proportions really land and makes a centred layout look wrong.
    func previewFramed() -> some View {
        frame(width: AppLayout.windowSize.width, height: AppLayout.windowSize.height)
    }

    /// Pins an editor preview to a representative maximised size, below a strip
    /// standing in for the window's toolbar.
    ///
    /// In the app the toolbar is the window's own, and the sidebars run up behind
    /// it. The preview canvas draws its chrome instead and will not render
    /// content under it, so the space is reserved here — otherwise the tops of
    /// the sidebars are hidden and the preview looks broken in a way the app is
    /// not.
    func previewEditorFramed() -> some View {
        padding(.top, AppLayout.previewToolbarInset)
            .frame(width: 1200, height: 760)
    }
}

#Preview("Welcome — device language") {
    previewWindow(.preview())
}

#Preview("Welcome — English") {
    previewWindow(.preview(AppPreferences(language: .english)))
}

#Preview("Welcome — remembered folder unavailable") {
    previewScreen(
        WelcomeView(notice: .rememberedFolderUnavailable),
        app: .preview(AppPreferences(language: .english))
    )
    .previewFramed()
}

/// Also the only way to see the transient launch state, since `RootView` owns
/// the resolution and settles onto the notice once it fails.
#Preview("Launch — restoring a remembered folder") {
    previewWindow(.previewWithUnresolvableBookmark(AppPreferences(language: .english)))
}

#Preview("Editor — nothing selected") {
    previewScreen(
        EditorView(folder: previewFolder),
        app: .preview(AppPreferences(language: .english))
    )
    .previewEditorFramed()
}

/// The settled editing state: a photo on the canvas and a tool panel open.
#Preview("Editor — photo and tool panel") {
    let app = AppViewModel.preview(AppPreferences(language: .english))
    let editor = previewEditor(app)

    return previewScreen(EditorView(folder: previewFolder), app: app, editor: editor)
        .previewEditorFramed()
        .task {
            // `load` is idempotent for a folder already on show, so this does
            // not race the view's own `.task` — whichever runs first wins and
            // the other returns immediately.
            await editor.load(previewFolder)
            if case .loaded(let photos) = editor.library, let photo = photos.first {
                await editor.select(photo)
            }
            editor.toggleTool(.color)
        }
}

/// The crop tool mid-session: the whole photo with everything outside the crop
/// dimmed, and the panel that can make the same crop without a pointer.
///
/// The one state that cannot be previewed any other way, because it only exists
/// between opening the tool and committing it — and it is the state where a
/// mistake in the overlay's placement is most obvious.
#Preview("Editor — cropping") {
    let app = AppViewModel.preview(AppPreferences(language: .english))
    let editor = previewEditor(app)

    return previewScreen(EditorView(folder: previewFolder), app: app, editor: editor)
        .previewEditorFramed()
        .task {
            await editor.load(previewFolder)
            if case .loaded(let photos) = editor.library, let photo = photos.first {
                await editor.select(photo)
            }
            editor.toggleTool(.crop)
            editor.setCropAspect(.fixed(width: 16, height: 9))
        }
}

/// The tool panel and rail together.
///
/// Previewed directly rather than through the editor because the editor's panel
/// only opens after an asynchronous folder scan, and a snapshot catches the
/// frame before that settles. This composition is synchronous, so what it shows
/// is what the editor shows — verified functionally by the UI test instead.
#Preview("Tool panel and rail") {
    let app = AppViewModel.preview(AppPreferences(language: .english))

    return HStack(spacing: 0) {
        ToolPanel(tool: .color)
        Divider()
        ToolRail()
    }
    .environment(app)
    .environment(previewEditor(app))
    .appPresentation(app.preferences)
    .frame(width: AppLayout.toolPanelWidth + AppLayout.toolRailWidth + 1, height: 420)
}

#Preview("Welcome — French, dark") {
    previewWindow(.preview(AppPreferences(language: .french, theme: .dark)))
}

/// Guards the accessibility requirement that the layout reflows at the largest
/// Dynamic Type sizes instead of clipping.
#Preview("Welcome — accessibility text") {
    RootView(app: .preview(AppPreferences(language: .english)), engine: PreviewPhotoEditor())
        .previewFramed()
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// Every sidebar glyph the system ships, so the toggle's icon can be chosen
/// against a render rather than guessed at from its name.
#Preview("Sidebar toggle candidates") {
    let names = [
        "sidebar.leading", "sidebar.left", "sidebar.right", "sidebar.trailing",
        "sidebar.squares.leading", "sidebar.squares.left",
        "sidebar.squares.right", "sidebar.squares.trailing",
    ]

    return VStack(alignment: .leading, spacing: 10) {
        ForEach(names, id: \.self) { name in
            HStack(spacing: 14) {
                Image(systemName: name)
                    .font(.title2)
                    .frame(width: 34)
                Text(name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
}

/// The editor at an accessibility text size.
///
/// The top bar takes its height as a floor rather than a fixed size, so it grows
/// with the text instead of clipping it — this is what shows whether that holds.
#Preview("Editor — accessibility text") {
    previewScreen(EditorView(folder: previewFolder), app: .preview(AppPreferences(language: .english)))
        .previewEditorFramed()
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
