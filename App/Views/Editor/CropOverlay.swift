//
//  CropOverlay.swift
//  Photon
//

import SwiftUI

/// The crop, drawn over the picture it is taken from: everything outside it
/// dimmed, a rule-of-thirds grid inside it, and eight handles plus a drag on the
/// middle to move it.
///
/// Sized to the picture, not to the pane around it. That is what makes a drag's
/// position a position in the photo — the overlay's own coordinates divided by
/// its own size are already normalized, with no aspect-fit calculation in the
/// middle to get wrong.
///
/// The picture underneath is never re-rendered while this is on screen. Dimming
/// the outside is what shows the user what they are keeping, and it is also why
/// dragging a handle costs nothing: the pixels do not move, only the frame drawn
/// over them.
///
/// Invisible to accessibility on purpose. Eight drag targets are not something
/// VoiceOver can operate, so the overlay is a pointer affordance and the panel
/// carries every one of these operations as a control that can be adjusted.
/// Claiming these handles as separate elements would put eight unreachable
/// elements in the tree and hide the panel's four that work.
struct CropOverlay: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Where the crop is, normalized to the picture this overlay is sized to.
    let rect: CGRect

    /// The coordinates a drag reads its positions in.
    ///
    /// Named rather than local, and this is not a detail. `DragGesture` reports
    /// against the coordinate space of the view it is attached to; two of the
    /// views here *are* the crop, so a local-space drag would be measuring the
    /// finger against a space that had already moved with the crop — the crop
    /// feeding its own next position. The name is defined on the stack inside the
    /// geometry reader, which is sized to the picture and holds still.
    private static let space = "photon.crop.overlay"

    /// The rect the current move drag started on.
    ///
    /// Kept so the translation can be applied to it outright rather than added to
    /// whatever the crop has become. Nil between drags, and captured on the first
    /// callback of each.
    @State private var moveOrigin: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let pixels = frame(in: size)

            ZStack(alignment: .topLeading) {
                dimming(pixels: pixels, in: size)
                interior(pixels: pixels, in: size)
                grid(pixels: pixels)
                border(pixels: pixels)
                handles(pixels: pixels, in: size)
            }
            .coordinateSpace(.named(Self.space))
        }
        .accessibilityHidden(true)
    }

    /// The crop in points, inside a picture of `size`.
    private func frame(in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    /// Everything outside the crop, knocked out of a filled rectangle.
    ///
    /// Even-odd fill rather than four rectangles: one path, no seams at the
    /// corners, and nothing to keep in step with the rect as it is dragged.
    private func dimming(pixels: CGRect, in size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(pixels)
        }
        .fill(.black.opacity(Self.dimOpacity), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func border(pixels: CGRect) -> some View {
        Rectangle()
            .stroke(.white.opacity(Self.lineOpacity), lineWidth: AppLayout.cropGridLineWidth)
            .frame(width: pixels.width, height: pixels.height)
            .position(x: pixels.midX, y: pixels.midY)
            .allowsHitTesting(false)
    }

    private func grid(pixels: CGRect) -> some View {
        Path { path in
            for step in 1...2 {
                let x = pixels.minX + pixels.width * CGFloat(step) / 3
                path.move(to: CGPoint(x: x, y: pixels.minY))
                path.addLine(to: CGPoint(x: x, y: pixels.maxY))

                let y = pixels.minY + pixels.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: pixels.minX, y: y))
                path.addLine(to: CGPoint(x: pixels.maxX, y: y))
            }
        }
        .stroke(.white.opacity(reduceTransparency ? 1 : Self.gridOpacity), lineWidth: AppLayout.cropGridLineWidth)
        .allowsHitTesting(false)
    }

    /// The drag that moves the crop without resizing it.
    ///
    /// Two things here are deliberate, and both were the reason dragging this
    /// twitched between two places instead of following the finger.
    ///
    /// The gesture reads the overlay's named space rather than its own. This view
    /// *is* the crop — it is sized to the crop and positioned at its middle — so a
    /// local-space drag measures the finger against a space that the crop has
    /// already shifted, and every move is then re-read as a move.
    ///
    /// And the translation is applied to the rect the drag started on, not added
    /// to the crop as it stands. A drag reports the whole of its travel on every
    /// callback, so adding it repeatedly sends the crop running away from the
    /// pointer; applying it outright makes the result depend only on where the
    /// finger is, which is a question with one answer however many callbacks
    /// arrive, and in whatever order.
    private func interior(pixels: CGRect, in size: CGSize) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(.rect)
            .frame(width: pixels.width, height: pixels.height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let origin = moveOrigin ?? rect
                        if moveOrigin == nil { moveOrigin = rect }
                        editor.moveCrop(
                            from: origin,
                            by: CGSize(
                                width: value.translation.width / size.width,
                                height: value.translation.height / size.height
                            )
                        )
                    }
                    .onEnded { _ in moveOrigin = nil }
            )
            .position(x: pixels.midX, y: pixels.midY)
    }

    private func handles(pixels: CGRect, in size: CGSize) -> some View {
        ForEach(Self.handles) { handle in
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(Self.shadowOpacity), radius: 1)
                .frame(width: AppLayout.cropHandleSize, height: AppLayout.cropHandleSize)
                .frame(width: AppLayout.cropHitTarget, height: AppLayout.cropHitTarget)
                .contentShape(.circle)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            guard size.width > 0, size.height > 0 else { return }
                            editor.resizeCrop(
                                moving: handle.edges,
                                to: CGPoint(
                                    x: value.location.x / size.width,
                                    y: value.location.y / size.height
                                )
                            )
                        }
                )
                .position(handle.point(in: pixels))
        }
    }

    // MARK: - Handles

    /// Where a handle sits on the crop, and which edges dragging it moves.
    ///
    /// One list rather than eight near-identical views: a corner carries two
    /// edges and an edge carries one, and a resize already takes a set of them,
    /// so there is nothing left for a handle to be but a position and that set.
    private struct Handle: Identifiable {
        let edges: CropGeometry.Edges
        /// Position on the crop, `0...1` on each axis.
        let x: CGFloat
        let y: CGFloat

        var id: Int { edges.rawValue }

        func point(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
    }

    private static let handles: [Handle] = [
        Handle(edges: [.left, .top], x: 0, y: 0),
        Handle(edges: [.top], x: 0.5, y: 0),
        Handle(edges: [.right, .top], x: 1, y: 0),
        Handle(edges: [.right], x: 1, y: 0.5),
        Handle(edges: [.right, .bottom], x: 1, y: 1),
        Handle(edges: [.bottom], x: 0.5, y: 1),
        Handle(edges: [.left, .bottom], x: 0, y: 1),
        Handle(edges: [.left], x: 0, y: 0.5),
    ]

    // MARK: - Presentation

    /// How far the picture is dimmed outside the crop.
    ///
    /// Enough to read the crop's edge at a glance and not so much that the user
    /// cannot see what they are cropping away and think better of it.
    private static let dimOpacity = 0.55
    private static let gridOpacity = 0.5
    private static let lineOpacity = 0.9
    private static let shadowOpacity = 0.5
}
