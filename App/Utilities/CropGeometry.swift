//
//  CropGeometry.swift
//  Photon
//

import CoreGraphics
import ImageIO

/// The arithmetic of a crop: fitting a shape to a rect, holding it to a ratio
/// while it is dragged, turning it with the frame, and putting it into the two
/// coordinate systems the pipeline speaks.
///
/// Every function here is total and side-effect free, which is the point — a
/// crop has three separate traps in it (a normalized ratio is not a pixel ratio,
/// Core Image counts y upwards, and a quarter turn both moves the rect and
/// swaps its shape) and none of them are visible on screen when they are wrong.
/// They are visible in a test.
nonisolated enum CropGeometry {
    /// Which edges a drag moves.
    ///
    /// A corner is two edges and an edge is one, so one resize function covers
    /// every handle without ever asking what the handle is called.
    nonisolated struct Edges: OptionSet, Sendable {
        let rawValue: Int

        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// The whole frame, in the units every crop rect is measured in.
    static let unitFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    // MARK: - Ratios

    /// `aspect` as a ratio of *normalized* lengths.
    ///
    /// This is the trap the whole type exists to contain. A rect that is 16:9 in
    /// pixels is not 16:9 in normalized units: x is a fraction of the frame's
    /// width and y of its height, so the two are off by the frame's own aspect.
    /// Comparing `rect.width / rect.height` against a pixel ratio holds a crop
    /// to the wrong shape, and does it most visibly on exactly the photos a
    /// photographer cares about.
    ///
    /// - Returns: nil when there is no constraint, or when the frame is empty.
    static func normalizedRatio(_ aspect: AspectRatio, in frame: CGSize) -> CGFloat? {
        guard frame.width > 0, frame.height > 0 else { return nil }

        let pixels: Double
        switch aspect {
        case .free: return nil
        case .original: pixels = frame.width / frame.height
        case .fixed(let width, let height): pixels = Double(width) / Double(height)
        }

        return CGFloat(pixels * frame.height / frame.width)
    }

    // MARK: - Size floors and caps

    /// The smallest a crop may be, in normalized units.
    ///
    /// A square in pixels is not a square in normalized units, so each axis gets
    /// its own floor. Capped at the frame, because a photo smaller than the
    /// minimum cannot be cropped below itself.
    static func minimumSize(in frame: CGSize) -> CGSize {
        guard frame.width > 0, frame.height > 0 else {
            return CGSize(width: 1e-4, height: 1e-4)
        }
        return CGSize(
            width: min(1, Crop.minimumPixelSize / frame.width),
            height: min(1, Crop.minimumPixelSize / frame.height)
        )
    }

    /// The smallest a crop *of `aspect`* may be, in normalized units.
    ///
    /// A locked ratio ties the axes together, so whichever floor is the binding
    /// one sets the size. A wide ratio binds on height — the same 32 pixels of
    /// height is a different number of normalized units than 32 pixels of width
    /// — and taking the width floor alone would quietly allow a crop shorter
    /// than the minimum.
    static func minimumSize(for aspect: AspectRatio, in frame: CGSize) -> CGSize {
        let floor = minimumSize(in: frame)
        guard let ratio = normalizedRatio(aspect, in: frame), ratio > 0 else { return floor }

        let width = max(floor.width, floor.height * ratio)
        return cappedToUnit(CGSize(width: width, height: width / ratio))
    }

    // MARK: - Fitting and dragging

    /// The largest rect of `aspect` that fits inside `container`, centred on it.
    ///
    /// Grows the axis the shape is short of and keeps the other, then caps at the
    /// frame. That ordering is what stops trying shapes on from whittling a crop
    /// away: picking 1:1 on a wide crop *adds* height rather than taking width
    /// off, and a crop the user framed carefully survives a look at what it would
    /// be square.
    static func fitted(_ aspect: AspectRatio, inside container: CGRect, frame: CGSize) -> CGRect {
        guard let ratio = normalizedRatio(aspect, in: frame), ratio > 0,
              container.width > 0, container.height > 0
        else {
            return slided(cappedToUnit(container))
        }

        var size = container.size
        if size.width / size.height > ratio {
            size.height = size.width / ratio
        } else {
            size.width = size.height * ratio
        }
        size = cappedToUnit(size)

        let floor = minimumSize(for: aspect, in: frame)
        size.width = max(size.width, floor.width)
        size.height = max(size.height, floor.height)

        return slided(cappedToUnit(centred(size, on: container)))
    }

    /// Drags `edges` to `point`, holding the edges that are not being dragged.
    ///
    /// Enforces `aspect` and ``Crop/minimumPixelSize``, and keeps the result
    /// inside the frame. `point` and the result are both normalized.
    ///
    /// A drag past the opposite edge stops at the minimum rather than turning the
    /// rect inside out, and a corner drag takes whichever of the two axes the
    /// pointer asked for less — so the crop never runs past the pointer.
    static func resized(
        _ rect: CGRect,
        moving edges: Edges,
        to point: CGPoint,
        aspect: AspectRatio,
        frame: CGSize
    ) -> CGRect {
        guard frame.width > 0, frame.height > 0, !edges.isEmpty else { return rect }

        let target = CGPoint(x: min(max(0, point.x), 1), y: min(max(0, point.y), 1))
        var minX = edges.contains(.left) ? target.x : rect.minX
        var maxX = edges.contains(.right) ? target.x : rect.maxX
        var minY = edges.contains(.top) ? target.y : rect.minY
        var maxY = edges.contains(.bottom) ? target.y : rect.maxY

        let floor = minimumSize(for: aspect, in: frame)
        if maxX - minX < floor.width {
            if edges.contains(.left) { minX = maxX - floor.width }
            else if edges.contains(.right) { maxX = minX + floor.width }
        }
        if maxY - minY < floor.height {
            if edges.contains(.top) { minY = maxY - floor.height }
            else if edges.contains(.bottom) { maxY = minY + floor.height }
        }

        var size = CGSize(width: maxX - minX, height: maxY - minY)

        if let ratio = normalizedRatio(aspect, in: frame), ratio > 0 {
            let movesHorizontally = edges.contains(.left) || edges.contains(.right)
            let movesVertically = edges.contains(.top) || edges.contains(.bottom)

            switch (movesHorizontally, movesVertically) {
            case (true, true):
                // A corner sets both axes, so the rect follows whichever of them
                // the pointer asked for less.
                let byWidth = CGSize(width: size.width, height: size.width / ratio)
                let byHeight = CGSize(width: size.height * ratio, height: size.height)
                size = byWidth.width <= byHeight.width ? byWidth : byHeight
            case (true, false):
                // An edge sets one axis; the other follows about the rect's
                // centre, which is what makes a side handle feel like it is
                // scaling rather than squashing.
                size.height = size.width / ratio
            case (false, true):
                size.width = size.height * ratio
            case (false, false):
                break
            }

            size = cappedToUnit(size)
        }

        size.width = max(size.width, floor.width)
        size.height = max(size.height, floor.height)

        // Which edge is held decides which way the rect grows from its anchor.
        let holdsRight = edges.contains(.left) && !edges.contains(.right)
        let holdsLeft = edges.contains(.right) && !edges.contains(.left)
        let holdsBottom = edges.contains(.top) && !edges.contains(.bottom)
        let holdsTop = edges.contains(.bottom) && !edges.contains(.top)

        let anchorX = holdsRight ? maxX : holdsLeft ? minX : rect.midX
        let anchorY = holdsBottom ? maxY : holdsTop ? minY : rect.midY

        let originX = holdsRight ? anchorX - size.width : holdsLeft ? anchorX : anchorX - size.width / 2
        let originY = holdsBottom ? anchorY - size.height : holdsTop ? anchorY : anchorY - size.height / 2

        return slided(CGRect(origin: CGPoint(x: originX, y: originY), size: size))
    }

    /// Translates `rect` without resizing it, kept inside the frame.
    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        slided(rect.offsetBy(dx: delta.width, dy: delta.height))
    }

    /// Moves `rect` back inside the frame without resizing it.
    private static func slided(_ rect: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = min(max(0, rect.minX), max(0, 1 - rect.width))
        rect.origin.y = min(max(0, rect.minY), max(0, 1 - rect.height))
        return rect
    }

    /// Scales `size` down to the frame if it overflows, keeping its shape.
    ///
    /// A tall ratio dragged along its short axis asks for more height than the
    /// frame has — 1:10 dragged to full width wants ten frames' worth — and the
    /// answer is the largest such rect that fits, not a rect hanging off the
    /// photo.
    private static func cappedToUnit(_ size: CGSize) -> CGSize {
        guard size.width > 1 || size.height > 1 else { return size }
        let scale = min(1 / size.width, 1 / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Scales `rect` down to the frame if it overflows, keeping its shape.
    private static func cappedToUnit(_ rect: CGRect) -> CGRect {
        let size = cappedToUnit(rect.size)
        guard size != rect.size else { return rect }
        return CGRect(origin: rect.origin, size: size)
    }

    // MARK: - Turning

    /// The frame's size once `turn` is applied.
    static func turnedSize(_ size: CGSize, by turn: QuarterTurn) -> CGSize {
        turn.swapsAxes ? CGSize(width: size.height, height: size.width) : size
    }

    /// Where `rect` lands when the frame is turned.
    ///
    /// Clockwise takes the top-left corner to the top-right, so `(x, y, w, h)`
    /// becomes `(1 - y - h, x, h, w)`. The region the user was looking at is the
    /// region they are still looking at — and because the frame's own width and
    /// height have swapped underneath it, its pixel ratio has turned over, which
    /// is why the ratio preset follows the rotation.
    static func turned(_ rect: CGRect, by turn: QuarterTurn) -> CGRect {
        var rect = rect
        for _ in 0..<turn.rawValue {
            rect = CGRect(
                x: 1 - rect.minY - rect.height,
                y: rect.minX,
                width: rect.height,
                height: rect.width
            )
        }
        return rect
    }

    // MARK: - Reading the file's own numbers

    /// The size a photo is *seen* at, once its EXIF orientation is applied.
    ///
    /// ImageIO bakes the orientation into the pixels it hands over, so a decoded
    /// image is already this size — but the size the file *records* is the stored
    /// one, and a portrait photo shot sideways is stored landscape. Reading the
    /// stored numbers and using them as the frame turns a portrait crop sideways.
    static func uprightSize(_ size: CGSize, for orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            CGSize(width: size.height, height: size.width)
        default:
            size
        }
    }

    // MARK: - Pixels

    /// `rect` in the photo's own pixels, rounded to whole pixels.
    ///
    /// Rounded against the *source* rather than against whatever image the engine
    /// happens to be working on, so a preview and a full-resolution render round
    /// to the same edges and show the same picture.
    static func pixelRect(_ rect: CGRect, in frame: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }

        let minX = (rect.minX * frame.width).rounded()
        let minY = (rect.minY * frame.height).rounded()
        let maxX = (rect.maxX * frame.width).rounded()
        let maxY = (rect.maxY * frame.height).rounded()

        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    /// The rect as Core Image should see it, on an image of `extent`.
    ///
    /// Two conversions in one place, because doing either of them anywhere else
    /// is how a crop ends up mirrored or a pixel off without anyone noticing:
    ///
    /// - The rect is rounded in `frame`'s pixels and then *scaled* to `extent`, so
    ///   the preview and a full-resolution render agree on which pixels they are
    ///   showing.
    /// - The crop UI and `CGImage` count y down from the top; `CIImage` counts it
    ///   up from the bottom. The flip is therefore of the distance *from the top*
    ///   — not of an absolute y, which would be wrong the moment an extent does
    ///   not start at zero, as one that has been turned need not.
    static func coreImageRect(_ rect: CGRect, frame: CGSize, extent: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0, extent.width > 0, extent.height > 0 else {
            return extent
        }

        let pixels = pixelRect(rect, in: frame)
        let scaleX = extent.width / frame.width
        let scaleY = extent.height / frame.height

        let left = pixels.minX * scaleX
        let top = pixels.minY * scaleY
        let width = pixels.width * scaleX
        let height = pixels.height * scaleY

        return CGRect(
            x: extent.minX + left,
            y: extent.maxY - top - height,
            width: width,
            height: height
        )
    }

    // MARK: - The canvas

    /// Where an image of `imageSize` lands when it is aspect-fitted into
    /// `container` and centred.
    ///
    /// Exactly what `.aspectRatio(contentMode: .fit)` draws, worked out rather
    /// than inferred. The crop overlay has to sit on the picture and not on the
    /// pane around it, and a drag's position only means something once it is
    /// measured against the picture.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Internals

    /// `size`, centred on `container`.
    ///
    /// A private function rather than an extension on `CGRect`: an extension
    /// declared here would be main-actor isolated by the target's default, and
    /// this is called from the engine's actor and from static maths.
    private static func centred(_ size: CGSize, on container: CGRect) -> CGRect {
        CGRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
