//
//  PhotoCanvas.swift
//  Photon
//

import CoreImage
import Metal
import SwiftUI

/// The selected photo, or whatever should stand in for it.
struct PhotoCanvas: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(FolderViewModel.self) private var folder

    /// The split view's width; the window's centre line is half of it.
    ///
    /// The panes around the canvas differ in width, so its centre is not the
    /// window's. The photo and the placeholders stand on the window's instead.
    let windowWidth: CGFloat

    /// What a picture keeps clear of the canvas's edges.
    private static let pictureInset: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            // Worked out in the same pass as the content, so a pane opening
            // around the canvas never leaves the picture a frame behind.
            let offset = windowOffset(in: proxy)

            Group {
                switch editor.canvas {
                case .nothingSelected:
                    empty(offset: offset)
                case .loading:
                    // Circular, and said so rather than left to the default. An
                    // indeterminate `ProgressView` is a spinner on some platforms and
                    // a *bar* on others, and a bar in the middle of the canvas while a
                    // photo loads is a bar the user has to watch appear and go.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .accessibilityLabel("editor.canvas.loading")
                        .offset(x: offset)
                case .ready(_, let photo):
                    picture(photo, offset: offset)
                case .failed:
                    message("editor.canvas.failed", systemImage: "exclamationmark.triangle.fill", offset: offset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
    }

    /// How far the window's centre line sits from the canvas's, in points.
    ///
    /// The pane's frame is read in the same pass, so the offset follows it
    /// instead of arriving a frame behind. Zero until the window is measured.
    private func windowOffset(in proxy: GeometryProxy) -> CGFloat {
        guard windowWidth > 0 else { return 0 }
        return windowWidth / 2 - proxy.frame(in: .named(AppLayout.splitViewSpace)).midX
    }

    /// Before the first photo is chosen.
    ///
    /// Also offers the other way in: opening a folder with different photos in
    /// it, without making the user find the File menu first.
    private func empty(offset: CGFloat) -> some View {
        message("editor.canvas.empty", systemImage: "photo", offset: offset) {
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
    private func picture(_ photo: RenderedPhoto, offset: CGFloat) -> some View {
        // One picture, and the canvas draws it. While the crop tool is open the
        // view model puts the whole photo up — the region being cropped away stays
        // on screen so a handle can be dragged back out over it — and every other
        // time it puts up the crop itself. The canvas used to choose between two
        // pictures of its own, and chose the ungraded one for the moment the crop
        // tool opened over a grade.
        let image = photo.image
        let imageSize = image.extent.size
        let name = editor.selection?.name ?? ""

        return GeometryReader { proxy in
            let fitted = CropGeometry.fittedRect(imageSize: imageSize, in: proxy.size)
            // This reader is centred in the canvas, padding and all.
            let target = proxy.size.width / 2 + offset
            // Limited to the slack the fit leaves, so a photo as wide as the
            // canvas keeps its edges off the panes beside it.
            let frame = CropGeometry.shifted(fitted, by: target - fitted.midX, in: proxy.size)

            drawn(image, name: name)
                .frame(width: frame.width, height: frame.height)
                .overlay { CropLayer() }
                .position(x: frame.midX, y: frame.midY)
        }
        .padding(Self.pictureInset)
    }

    /// The picture itself: put on the GPU where there is one to put it on, and
    /// drawn as pixels where there is not.
    ///
    /// A staged preview is a `CIImage`, which is a description rather than
    /// pixels, so the canvas needs something that draws one — and a Metal-backed
    /// view is what that is. It is also the whole point: a slider drag renders a
    /// new preview per frame, and a view that takes the description lets the
    /// next frame's work begin before the last one has been put on screen, where
    /// asking for finished pixels makes every frame wait for the one before it.
    @ViewBuilder private func drawn(_ image: CIImage, name: String) -> some View {
        if MTLCreateSystemDefaultDevice() != nil {
            MetalPhotoView(image: image, context: editor.previewContext, label: name)
        } else if let flat = editor.previewContext.createCGImage(image, from: image.extent) {
            // No Metal device: a simulator, or a machine whose GPU is
            // unavailable. The engine stages previews on the CPU there, and the
            // canvas shows them the way it did before the Metal view existed.
            Image(flat, scale: 1, orientation: .up, label: Text(name))
                .resizable()
                .accessibilityIdentifier("editor.canvas.image")
        }
    }

    private func message(
        _ key: LocalizedStringKey,
        systemImage: String,
        offset: CGFloat,
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
        // Shifted, then centred in the pane: an `offset` moves what is drawn
        // *and* what is hit-tested, so the button stays where it looks. Applied
        // inside the centring frame rather than outside it — a block wider than
        // the frame it is centred in has no stable position to settle on.
        .offset(x: offset)
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
