//
//  CropGeometryTests.swift
//  PhotonTests
//

import CoreGraphics
import ImageIO
import Testing

@testable import Photon

/// The arithmetic behind the crop.
///
/// Three of these functions exist because getting them wrong is invisible on
/// screen: a normalized ratio is not a pixel ratio, Core Image counts y upwards,
/// and a quarter turn swaps a rect's shape as well as its place. Each one has a
/// test that fails loudly if the trap is stepped in.
@Suite("Crop geometry")
struct CropGeometryTests {
    /// `alpha.png`'s shape, in pixels.
    private let landscape = CGSize(width: 64, height: 48)

    // MARK: - Normalized ratios

    @Test("A normalized ratio accounts for the frame's own shape")
    func normalizedRatioIsNotThePixelRatio() throws {
        // A 4:3 frame: 16:9 in pixels is 1.3333 in normalized units, not 1.7778.
        let ratio = try #require(CropGeometry.normalizedRatio(.fixed(width: 16, height: 9), in: landscape))
        #expect(abs(ratio - 1.3333) < 0.001)

        // And the rect that ratio produces really is 16:9 once it is in pixels.
        let rect = CropGeometry.fitted(.fixed(width: 16, height: 9), inside: CropGeometry.unitFrame, frame: landscape)
        let pixels = CropGeometry.pixelRect(rect, in: landscape)
        #expect(abs(pixels.width / pixels.height - 16.0 / 9.0) < 0.02)
    }

    @Test("A free crop has no ratio, and an empty frame has none either")
    func ratiosThatDoNotConstrain() {
        #expect(CropGeometry.normalizedRatio(.free, in: landscape) == nil)
        #expect(CropGeometry.normalizedRatio(.fixed(width: 16, height: 9), in: .zero) == nil)
    }

    @Test("Original follows the frame it is in, so turning it reciprocates")
    func originalFollowsTheFrame() {
        let upright = CropGeometry.normalizedRatio(.original, in: landscape)
        let turned = CropGeometry.normalizedRatio(.original, in: CGSize(width: 48, height: 64))

        #expect(upright == 1)
        #expect(turned == 1)
    }

    // MARK: - Minimums

    @Test("The minimum is a floor on pixels, which is not a square in normalized units")
    func minimumTracksPixels() {
        let floor = CropGeometry.minimumSize(in: landscape)

        #expect(abs(floor.width * landscape.width - Crop.minimumPixelSize) < 0.001)
        #expect(abs(floor.height * landscape.height - Crop.minimumPixelSize) < 0.001)
        #expect(floor.width != floor.height, "A square in pixels is a rectangle in normalized units")
    }

    @Test("A locked ratio's floor holds the axis that binds, so a wide crop is not left too short")
    func lockedRatioMinimumBindsOnHeight() {
        let free = CropGeometry.minimumSize(in: landscape)
        let wide = CropGeometry.minimumSize(for: .fixed(width: 16, height: 9), in: landscape)

        // Taking the width floor alone would give a 16:9 crop 24 pixels tall.
        #expect(wide.width > free.width)
        #expect(wide.width * landscape.width >= Crop.minimumPixelSize)
        #expect(wide.height * landscape.height >= Crop.minimumPixelSize - 0.001)
    }

    @Test("The minimum never exceeds the frame, however small the photo")
    func minimumFitsATinyPhoto() {
        let tiny = CGSize(width: 8, height: 8)
        let floor = CropGeometry.minimumSize(in: tiny)

        #expect(floor.width <= 1)
        #expect(floor.height <= 1)
    }

    // MARK: - Fitting

    @Test(
        "Picking a ratio fits the largest crop of that shape, centred",
        arguments: zip(
            [
                AspectRatio.fixed(width: 16, height: 9),
                AspectRatio.fixed(width: 1, height: 1),
                AspectRatio.fixed(width: 4, height: 3),
            ],
            [
                CGSize(width: 64, height: 36),
                CGSize(width: 48, height: 48),
                CGSize(width: 64, height: 48),
            ]
        )
    )
    func fittingARatio(ratio: AspectRatio, expected: CGSize) {
        let rect = CropGeometry.fitted(ratio, inside: CropGeometry.unitFrame, frame: landscape)
        let pixels = CropGeometry.pixelRect(rect, in: landscape)

        #expect(pixels.size == expected)
        #expect(abs(rect.midX - 0.5) < 0.001, "The fit stays centred on what it grew from")
        #expect(abs(rect.midY - 0.5) < 0.001)
    }

    @Test("A fitted ratio grows to the floor rather than shrinking past it")
    func fittingGrowsToTheFloor() {
        // A crop already dragged down to the smallest a free crop may be.
        let small = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.667)
        let rect = CropGeometry.fitted(.fixed(width: 16, height: 9), inside: small, frame: landscape)
        let pixels = CropGeometry.pixelRect(rect, in: landscape)

        #expect(pixels.height >= Crop.minimumPixelSize - 1)
        #expect(pixels.width >= Crop.minimumPixelSize)
        #expect(pixels.minX >= -1 && pixels.maxX <= landscape.width + 1, "Still inside the photo")
    }

    @Test("Fitting a free crop leaves the crop alone")
    func fittingFreeChangesNothing() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(CropGeometry.fitted(.free, inside: rect, frame: landscape) == rect)
    }

    // MARK: - Dragging

    @Test("An edge drag holds the opposite edge")
    func edgeDragHoldsTheOtherEdge() {
        let full = CropGeometry.unitFrame

        let fromLeft = CropGeometry.resized(full, moving: .left, to: CGPoint(x: 0.25, y: 0), aspect: .free, frame: landscape)
        #expect(fromLeft == CGRect(x: 0.25, y: 0, width: 0.75, height: 1))

        let fromRight = CropGeometry.resized(full, moving: .right, to: CGPoint(x: 0.5, y: 0), aspect: .free, frame: landscape)
        #expect(fromRight == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test("A corner drag holds the opposite corner")
    func cornerDragHoldsTheOppositeCorner() {
        let rect = CropGeometry.resized(
            CropGeometry.unitFrame,
            moving: [.left, .top],
            to: CGPoint(x: 0.2, y: 0.25),
            aspect: .free,
            frame: landscape
        )

        // Within noise: the origin is `maxX - width`, and 1 - 0.8 is not 0.2.
        #expect(approximatelyEqual(rect, CGRect(x: 0.2, y: 0.25, width: 0.8, height: 0.75)))
    }

    @Test("A drag with no edges is a no-op, because moving is a different gesture")
    func noEdgesChangesNothing() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        #expect(CropGeometry.resized(rect, moving: [], to: CGPoint(x: 0.9, y: 0.9), aspect: .free, frame: landscape) == rect)
    }

    @Test("A locked ratio's edge drag grows the other axis about the centre")
    func lockedEdgeDragScalesSymmetrically() {
        let start = CropGeometry.fitted(.fixed(width: 16, height: 9), inside: CropGeometry.unitFrame, frame: landscape)
        let rect = CropGeometry.resized(start, moving: .left, to: CGPoint(x: 0.25, y: 0), aspect: .fixed(width: 16, height: 9), frame: landscape)
        let pixels = CropGeometry.pixelRect(rect, in: landscape)

        #expect(abs(pixels.width / pixels.height - 16.0 / 9.0) < 0.03)
        #expect(abs(rect.maxX - 1) < 0.001, "The right edge is held")
        #expect(abs(rect.midY - start.midY) < 0.001, "And the other axis grows about the centre")
    }

    @Test("A corner drag with a locked ratio never runs past the pointer")
    func lockedCornerDragStaysInsideThePointer() {
        // A real photo's size, so the minimum is not what is doing the
        // constraining — this is about the ratio, not the floor.
        let rect = CropGeometry.resized(
            CropGeometry.unitFrame,
            moving: [.left, .top],
            to: CGPoint(x: 0.1, y: 0.9),
            aspect: .fixed(width: 16, height: 9),
            frame: CGSize(width: 4000, height: 3000)
        )

        #expect(rect.minX >= 0.1 - 0.001)
        #expect(rect.minY >= 0.9 - 0.001)
        #expect(abs(rect.maxX - 1) < 0.001, "The edges that were held stayed put")
        #expect(abs(rect.maxY - 1) < 0.001)
    }

    @Test("A drag past the opposite edge stops at the minimum instead of inverting")
    func dragPastTheOppositeEdgeStops() {
        let floor = CropGeometry.minimumSize(in: landscape)
        let rect = CropGeometry.resized(
            CropGeometry.unitFrame,
            moving: .left,
            to: CGPoint(x: 5, y: 0),
            aspect: .free,
            frame: landscape
        )

        #expect(rect.width >= floor.width - 0.001, "Never narrower than the floor")
        #expect(rect.width > 0)
        #expect(rect.minX >= 0 && rect.maxX <= 1)
    }

    @Test("A drag off the canvas is clamped to it")
    func dragsAreClampedToTheCanvas() {
        let rect = CropGeometry.resized(
            CropGeometry.unitFrame,
            moving: .right,
            to: CGPoint(x: 4, y: 4),
            aspect: .free,
            frame: landscape
        )

        #expect(rect.maxX <= 1.001)
    }

    @Test("A very tall ratio is capped at the frame rather than hanging off it")
    func extremeRatiosAreCapped() {
        let rect = CropGeometry.resized(
            CropGeometry.unitFrame,
            moving: .right,
            to: CGPoint(x: 1, y: 1),
            aspect: .fixed(width: 1, height: 10),
            frame: landscape
        )
        let pixels = CropGeometry.pixelRect(rect, in: landscape)

        #expect(pixels.maxX <= landscape.width + 1)
        #expect(pixels.maxY <= landscape.height + 1)
    }

    @Test("Moving slides the crop and stops at the edges")
    func movingSlidesAndStops() {
        let rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

        #expect(CropGeometry.moved(rect, by: CGSize(width: 0.1, height: 0.1)) == CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))
        #expect(CropGeometry.moved(rect, by: CGSize(width: 5, height: 5)) == CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
        #expect(CropGeometry.moved(rect, by: CGSize(width: -5, height: -5)) == CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
    }

    // MARK: - Turning

    @Test("Turning the frame swaps which side is the width")
    func turnedSizeSwapsTheAxes() {
        #expect(CropGeometry.turnedSize(landscape, by: .none) == landscape)
        #expect(CropGeometry.turnedSize(landscape, by: .clockwise) == CGSize(width: 48, height: 64))
        #expect(CropGeometry.turnedSize(landscape, by: .upsideDown) == landscape)
        #expect(CropGeometry.turnedSize(landscape, by: .counterclockwise) == CGSize(width: 48, height: 64))
    }

    @Test("A quarter turn takes the top-left corner to the top-right")
    func turningMovesTheRect() {
        // The whole frame is unchanged, and a rect in the top-left goes top-right.
        #expect(CropGeometry.turned(CropGeometry.unitFrame, by: .clockwise) == CropGeometry.unitFrame)
        #expect(CropGeometry.turned(CGRect(x: 0, y: 0, width: 0.5, height: 0.25), by: .clockwise)
            == CGRect(x: 0.75, y: 0, width: 0.25, height: 0.5))
    }

    @Test("Four turns are no turn at all")
    func fourTurnsComeBack() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        var turned = rect
        for _ in 0..<4 {
            turned = CropGeometry.turned(turned, by: .clockwise)
        }

        #expect(abs(turned.minX - rect.minX) < 1e-9)
        #expect(abs(turned.minY - rect.minY) < 1e-9)
        #expect(abs(turned.width - rect.width) < 1e-9)
        #expect(abs(turned.height - rect.height) < 1e-9)
    }

    @Test("Turning one way and back leaves the rect where it was")
    func turningIsReversible() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let there = CropGeometry.turned(rect, by: .clockwise)
        let back = CropGeometry.turned(there, by: .counterclockwise)

        #expect(abs(back.minX - rect.minX) < 1e-9)
        #expect(abs(back.minY - rect.minY) < 1e-9)
        #expect(abs(back.width - rect.width) < 1e-9)
        #expect(abs(back.height - rect.height) < 1e-9)
    }

    @Test("A turned rect stays inside the turned frame")
    func turningStaysInside() {
        let rect = CGRect(x: 0.6, y: 0.7, width: 0.4, height: 0.3)
        let turned = CropGeometry.turned(rect, by: .counterclockwise)

        #expect(turned.minX >= -1e-9 && turned.maxX <= 1 + 1e-9)
        #expect(turned.minY >= -1e-9 && turned.maxY <= 1 + 1e-9)
    }

    @Test("Turning keeps the pixels it had, so the region does not move")
    func turningKeepsTheSamePixels() {
        // The rect's own shape is exchanged, and measured against the exchanged
        // frame it covers exactly what it covered before.
        let rect = CGRect(x: 0, y: 0, width: 0.5, height: 0.25)
        let before = CropGeometry.pixelRect(rect, in: landscape)

        let turnedFrame = CropGeometry.turnedSize(landscape, by: .clockwise)
        let after = CropGeometry.pixelRect(CropGeometry.turned(rect, by: .clockwise), in: turnedFrame)

        #expect(after.width == before.height)
        #expect(after.height == before.width)
        #expect(after.minX == landscape.height - before.maxY)
        #expect(after.minY == before.minX)
    }

    // MARK: - Reading the file

    @Test("Only the four orientations that are on their side swap the size")
    func uprightSizeAppliesOrientation() {
        let stored = CGSize(width: 6000, height: 4000)

        #expect(CropGeometry.uprightSize(stored, for: .up) == stored)
        #expect(CropGeometry.uprightSize(stored, for: .upMirrored) == stored)
        #expect(CropGeometry.uprightSize(stored, for: .down) == stored)
        #expect(CropGeometry.uprightSize(stored, for: .downMirrored) == stored)

        let turned = CGSize(width: 4000, height: 6000)
        #expect(CropGeometry.uprightSize(stored, for: .left) == turned)
        #expect(CropGeometry.uprightSize(stored, for: .right) == turned)
        #expect(CropGeometry.uprightSize(stored, for: .leftMirrored) == turned)
        #expect(CropGeometry.uprightSize(stored, for: .rightMirrored) == turned)
    }

    // MARK: - Pixels

    @Test("The pixel rect is rounded against the source, so preview and export agree")
    func pixelRectRoundsAgainstTheSource() {
        // A third of 100 is 33.33; rounding at the source gives 33, not 32 or 34.
        let rect = CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        let pixels = CropGeometry.pixelRect(rect, in: CGSize(width: 100, height: 50))

        #expect(pixels.minX == 33)
        #expect(pixels.maxX == 67)
        #expect(pixels.height == 50)
    }

    @Test("A crop never rounds away to nothing")
    func pixelRectKeepsAtLeastOnePixel() {
        let pixels = CropGeometry.pixelRect(CGRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001), in: landscape)

        #expect(pixels.width >= 1)
        #expect(pixels.height >= 1)
    }

    @Test("The crop is flipped into Core Image's coordinates exactly once")
    func coreImageRectFlipsY() {
        // Top-left quarter in a 64×48 photo, at full size.
        let rect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let flipped = CropGeometry.coreImageRect(rect, frame: landscape, extent: CGRect(origin: .zero, size: landscape))

        #expect(flipped == CGRect(x: 0, y: 24, width: 32, height: 24), "y is measured from the bottom")

        // And the same crop at half size lands on half the pixels.
        let preview = CGRect(origin: .zero, size: CGSize(width: 32, height: 24))
        let scaled = CropGeometry.coreImageRect(rect, frame: landscape, extent: preview)

        #expect(scaled == CGRect(x: 0, y: 12, width: 16, height: 12))
    }

    @Test("The flip is measured from the far edge of an extent that does not start at zero")
    func coreImageRectHandlesAnOffsetExtent() {
        // What a quarter turn can leave behind: the picture sitting off-origin.
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let flipped = CropGeometry.coreImageRect(rect, frame: landscape, extent: CGRect(x: 10, y: 20, width: 64, height: 48))

        #expect(flipped == CGRect(x: 10, y: 20, width: 64, height: 48))
    }

    @Test("An empty frame or extent is left alone rather than divided by")
    func coreImageRectSurvivesEmptyInput() {
        let extent = CGRect(origin: .zero, size: landscape)

        #expect(CropGeometry.coreImageRect(CropGeometry.unitFrame, frame: .zero, extent: extent) == extent)
        #expect(CropGeometry.coreImageRect(CropGeometry.unitFrame, frame: landscape, extent: .zero) == .zero)
    }

    // MARK: - The canvas

    @Test("A wide picture is fitted by its width, a tall one by its height")
    func fittingIntoACanvas() {
        let container = CGSize(width: 200, height: 200)

        let wide = CropGeometry.fittedRect(imageSize: CGSize(width: 400, height: 200), in: container)
        #expect(wide == CGRect(x: 0, y: 50, width: 200, height: 100))

        let tall = CropGeometry.fittedRect(imageSize: CGSize(width: 200, height: 400), in: container)
        #expect(tall == CGRect(x: 50, y: 0, width: 100, height: 200))
    }

    @Test("An empty container has nowhere to fit a picture")
    func fittingIntoNothing() {
        #expect(CropGeometry.fittedRect(imageSize: landscape, in: .zero) == .zero)
        #expect(CropGeometry.fittedRect(imageSize: .zero, in: CGSize(width: 10, height: 10)) == .zero)
    }
}

/// Two rects within floating-point noise of each other.
///
/// A rect's origin is derived from the edge opposite the one being dragged —
/// `maxX - width` and the like — so it lands a bit or two off the number that was
/// asked for, and `==` calls that different.
private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1e-9) -> Bool {
    abs(lhs.minX - rhs.minX) < tolerance
        && abs(lhs.minY - rhs.minY) < tolerance
        && abs(lhs.width - rhs.width) < tolerance
        && abs(lhs.height - rhs.height) < tolerance
}
