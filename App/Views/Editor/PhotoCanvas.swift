//
//  PhotoCanvas.swift
//  Photon
//

import SwiftUI

/// The selected photo, or whatever should stand in for it.
struct PhotoCanvas: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(FolderViewModel.self) private var folder

    /// How far a placeholder has to move to leave the canvas's centre for the
    /// window's.
    ///
    /// A photo is centred on the canvas, but the placeholders that stand in for
    /// one belong on the *window's* centre line, level with the title capsule —
    /// and the panes around the canvas (the sidebar, the tool panel, the rail)
    /// each move that line. Measured from where the canvas actually sits rather
    /// than worked out from which panes are open, so it holds while they animate.
    let windowCentreOffset: CGFloat

    var body: some View {
        Group {
            switch editor.canvas {
            case .nothingSelected:
                empty
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("editor.canvas.loading")
                    .offset(x: windowCentreOffset)
            case .ready(_, let image):
                photo(image)
            case .failed:
                message("editor.canvas.failed", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    /// Before the first photo is chosen.
    ///
    /// Also offers the other way in: opening a folder with different photos in
    /// it, without making the user find the File menu first.
    private var empty: some View {
        message("editor.canvas.empty", systemImage: "photo") {
            Button("command.openFolder") { folder.chooseFolder() }
                .buttonStyle(.bordered)
                .disabled(folder.folderPick == .opening)
                .accessibilityHint("welcome.chooseFolder.hint")
                .accessibilityIdentifier("editor.canvas.openFolder")
        }
    }

    /// `CGImage` on both platforms, so the canvas needs no `#if` for something
    /// as ordinary as showing a picture.
    ///
    /// The labelled initialiser rather than `Image(decorative:)`: a decorative
    /// image is deliberately kept out of the accessibility tree, which would
    /// leave VoiceOver — and the UI tests — with nothing to find.
    private func photo(_ image: CGImage) -> some View {
        Image(image, scale: 1, orientation: .up, label: Text(editor.selection?.name ?? ""))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(16)
            .accessibilityIdentifier("editor.canvas.image")
    }

    private func message(
        _ key: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .padding(24)
        // Shifted, then centred in the canvas: an `offset` moves what is drawn
        // *and* what is hit-tested, so the button stays where it looks. Applied
        // inside the centring frame rather than outside it — a block wider than
        // the frame it is centred in has no stable position to settle on.
        .offset(x: windowCentreOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Deliberately not `.accessibilityElement(children: .combine)`: that
        // would fold the button in with the text and make it unreachable.
    }
}
