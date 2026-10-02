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
                // Circular, and said so rather than left to the default. An
                // indeterminate `ProgressView` is a spinner on some platforms and
                // a *bar* on others, and a bar in the middle of the canvas while a
                // photo loads is a bar the user has to watch appear and go.
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .accessibilityLabel("editor.canvas.loading")
                    .offset(x: windowCentreOffset)
            case .ready(_, let photo):
                picture(photo)
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

    /// The photo, laid out at the size it is actually drawn at.
    ///
    /// The rect is worked out rather than left to `.aspectRatio(contentMode: .fit)`,
    /// which would hand the image view the whole pane and leave the crop overlay
    /// nothing to sit on. A drag is only a position in the photo once it is
    /// measured against the picture, so the picture has to *be* a frame — and
    /// that frame is also what the canvas reports to a test as the photo's shape.
    ///
    /// `CGImage` on both platforms, so the canvas needs no `#if` for something
    /// as ordinary as showing a picture.
    ///
    /// The labelled initialiser rather than `Image(decorative:)`: a decorative
    /// image is deliberately kept out of the accessibility tree, which would
    /// leave VoiceOver — and the UI tests — with nothing to find.
    private func picture(_ photo: RenderedPhoto) -> some View {
        // While the crop tool is open the canvas shows the whole photo with the
        // crop drawn over it, so what is being cropped away stays on screen and
        // the user can drag a handle back out past it. Every other time it shows
        // the crop itself.
        let image = editor.isCropping ? (editor.sessionBase ?? photo.base) : photo.image
        let imageSize = CGSize(width: image.width, height: image.height)

        return GeometryReader { proxy in
            let frame = CropGeometry.fittedRect(imageSize: imageSize, in: proxy.size)

            Image(image, scale: 1, orientation: .up, label: Text(editor.selection?.name ?? ""))
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .accessibilityIdentifier("editor.canvas.image")
                .overlay { CropLayer() }
                .position(x: frame.midX, y: frame.midY)
        }
        .padding(16)
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

/// The crop overlay, and only the crop overlay.
///
/// A view of its own so that a drag does not redraw the photo underneath it.
/// Observation tracks what a body *reads*, and the canvas reads the crop to size
/// this — so with the overlay inlined, every frame of a drag re-evaluated the
/// canvas, rebuilt the image view, and laid the picture out again. Here the crop
/// is read by this body alone and the picture is left where it is, which is both
/// what makes dragging smooth and what the drag was always meant to be: the
/// overlay moving over a photo that does not.
private struct CropLayer: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        if editor.isCropping, let crop = editor.draftCrop {
            CropOverlay(rect: crop.rect)
        }
    }
}
