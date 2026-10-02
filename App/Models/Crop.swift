//
//  Crop.swift
//  Photon
//

import CoreGraphics
import ImageIO

/// A quarter turn of the photo, clockwise.
///
/// Stored as a turn rather than an angle because a crop keeps its rect through
/// one: an arbitrary angle would need the rect re-derived after every degree.
/// Straighten is the tool that needs an angle, and it is not this one.
nonisolated enum QuarterTurn: Int, Equatable, Sendable, Codable, CaseIterable {
    case none = 0
    case clockwise = 1
    case upsideDown = 2
    case counterclockwise = 3

    /// This turn, one more to the right.
    var rotatedClockwise: QuarterTurn {
        QuarterTurn(rawValue: (rawValue + 1) % 4) ?? .none
    }

    /// This turn, one more to the left.
    var rotatedCounterclockwise: QuarterTurn {
        QuarterTurn(rawValue: (rawValue + 3) % 4) ?? .none
    }

    /// Whether the turn exchanges the frame's width and height.
    var swapsAxes: Bool { self == .clockwise || self == .counterclockwise }

    /// The turn as ImageIO and Core Image read one, so the pipeline never has to
    /// build a transform of its own.
    var orientation: CGImagePropertyOrientation {
        switch self {
        case .none: .up
        case .clockwise: .right
        case .upsideDown: .down
        case .counterclockwise: .left
        }
    }
}

/// The shape a crop is held to.
///
/// An exact pair of whole numbers rather than a quotient, because 16:9 is 16:9
/// and 1.7777777777777777 is not: a `Double` cannot tell 16:9 from 1024:576, and
/// the panel has to read back the ratio the user picked.
nonisolated enum AspectRatio: Equatable, Sendable, Codable {
    /// No constraint: the crop is whatever the user drags.
    case free
    /// The frame's own ratio, as it is currently turned — so a 4:3 photo turned
    /// a quarter offers 3:4, which is what "original" means once you turn it.
    case original
    /// An exact ratio.
    case fixed(width: Int, height: Int)

    /// The pairs the panel offers, in the order it offers them.
    ///
    /// The set Lightroom's crop tool lists: the photo's own, the square, then the
    /// classic print and screen shapes in both orientations. Both orientations
    /// *and* a swap button, because the swap is what keeps the region when the
    /// photo is turned, which a preset cannot do.
    static let presets: [AspectRatio] = [
        .free,
        .original,
        .fixed(width: 1, height: 1),
        .fixed(width: 4, height: 5),
        .fixed(width: 5, height: 4),
        .fixed(width: 2, height: 3),
        .fixed(width: 3, height: 2),
        .fixed(width: 3, height: 4),
        .fixed(width: 4, height: 3),
        .fixed(width: 9, height: 16),
        .fixed(width: 16, height: 9),
    ]

    /// The same ratio, reduced, so a pair typed as `32:18` reads back as `16:9`.
    ///
    /// Zero and negatives are coerced rather than rejected: the pair comes from
    /// two number fields, and `0:9` should mean the narrowest crop there is, not
    /// a ratio with no meaning at all.
    static func ratio(_ width: Int, _ height: Int) -> AspectRatio {
        let width = max(1, abs(width))
        let height = max(1, abs(height))
        let divisor = greatestCommonDivisor(width, height)
        return .fixed(width: width / divisor, height: height / divisor)
    }

    var isFree: Bool { self == .free }

    /// The ratio turned on its side, which is what the orientation swap does.
    ///
    /// `.free` and `.original` have no pair to exchange: a free crop is held to
    /// nothing, and the original already follows the frame it is in.
    var swapped: AspectRatio {
        guard case .fixed(let width, let height) = self else { return self }
        return .fixed(width: height, height: width)
    }

    /// Compared by cross-multiplying, so the pair does not have to be reduced to
    /// be the same ratio.
    ///
    /// The pair is stored as entered, and a recipe decoded from disk must not
    /// compare unequal to the same recipe built by the panel — which is what a
    /// synthesised `==` would do to `.fixed(32, 18)` and `.fixed(16, 9)`.
    static func == (lhs: AspectRatio, rhs: AspectRatio) -> Bool {
        switch (lhs, rhs) {
        case (.free, .free), (.original, .original):
            true
        case (.fixed(let leftWidth, let leftHeight), .fixed(let rightWidth, let rightHeight)):
            leftWidth * rightHeight == rightWidth * leftHeight
        default:
            false
        }
    }

    /// Only ever called with two numbers that are already at least one, so the
    /// result is too and needs no floor of its own.
    private static func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var left = left
        var right = right
        while right != 0 {
            (left, right) = (right, left % right)
        }
        return left
    }
}

/// What part of a photo is being kept, and how it is turned.
///
/// The rect is **normalized**, never pixels: origin top-left of the frame *after*
/// ``rotation``, one unit wide and one unit tall. That is what lets a single
/// recipe drive the downsampled preview and a full-resolution render
/// identically, and what makes the crop re-editable forever rather than baked in.
nonisolated struct Crop: Equatable, Sendable, Codable {
    /// Where in the turned frame the crop sits, in `0...1` on each axis.
    var rect: CGRect

    /// The shape the rect is held to while it is dragged.
    var aspect: AspectRatio

    /// How the frame is turned before the rect is taken from it.
    var rotation: QuarterTurn

    /// The whole photo, as it came out of the file.
    static let identity = Crop(
        rect: CGRect(x: 0, y: 0, width: 1, height: 1),
        aspect: .original,
        rotation: .none
    )

    /// Shortest edge a crop may have, in the photo's own pixels.
    ///
    /// In pixels rather than normalized units so it means the same thing on a
    /// 4000-pixel photo and on the preview the canvas is showing.
    static let minimumPixelSize: Double = 32

    /// Whether this crop asks for the photo exactly as the file holds it.
    ///
    /// Tolerant, and it has to be. Meeting the frame's own ratio through the
    /// solver is arithmetic, and `(w / h) * (h / w)` is not exactly one for about
    /// a quarter of all frame sizes — so on those photos picking "Original" lands
    /// an immeasurable sliver short of the whole frame, and an exact test would
    /// call that an edit and render it as one.
    var isIdentity: Bool {
        guard rotation == .none else { return false }
        let tolerance = 1e-6
        return abs(rect.minX) < tolerance
            && abs(rect.minY) < tolerance
            && abs(rect.width - 1) < tolerance
            && abs(rect.height - 1) < tolerance
    }
}
