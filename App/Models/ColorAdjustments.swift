//
//  ColorAdjustments.swift
//  Photon
//

import Foundation

/// One of the eight colours the colour tool splits the hue circle into.
///
/// The bands every editor offers, at the centres they sit at. A band is a
/// *window* on hue, not a set of pixels: a pixel belongs to the band its hue
/// falls in, weighted so that the two bands either side of it share a pixel
/// between them rather than stepping from one to the next. ``weight(of:at:)``
/// is that rule, and it is what the Metal kernel is held to — its table and its
/// arithmetic are generated from ``centre`` and from the flanks either side.
nonisolated enum ColorBand: String, CaseIterable, Equatable, Sendable, Codable, CodingKeyRepresentable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case magenta

    /// Where the band sits on the hue circle, in degrees.
    ///
    /// The spacing is not even, and deliberately so: a photographer's colours
    /// are not evenly spaced. The sixths of the circle that hold green, cyan and
    /// blue are wide because three names have to cover half the circle, while
    /// red, orange and yellow crowd the warm corner where the eye tells colours
    /// apart most finely.
    var centre: Double {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .cyan: 180
        case .blue: 240
        case .purple: 280
        case .magenta: 320
        }
    }

    /// The band before this one on the circle, which is where its ramp starts.
    ///
    /// Worked out from the centres rather than from a list order, so the two can
    /// never disagree about which way round the circle goes. The fallback is the
    /// circle closing: nothing sits before red except magenta.
    var previous: ColorBand {
        ColorBand.allCases.last { $0.centre < centre } ?? .magenta
    }

    /// The band after this one, which is where its ramp ends.
    var next: ColorBand {
        ColorBand.allCases.first { $0.centre > centre } ?? .red
    }

    /// How far this band's ramp runs back from its centre, in degrees.
    ///
    /// Signed, and that is the whole of the trick. The distance from the previous
    /// band's centre to this one, measured *forwards* around the circle: magenta
    /// to red is 40° forwards, not 320° backwards. Told the other way round, a
    /// band claims pixels its neighbour owns and the eight of them stop adding up
    /// to one — which is what the kernel was told until this was written down
    /// once and used in both places.
    var leftWidth: Double { ColorBand.signed(centre - previous.centre) }

    /// How far this band's ramp runs forward from its centre, in degrees.
    var rightWidth: Double { ColorBand.signed(next.centre - centre) }

    /// One band's share of `degrees`, ramping between its neighbours' centres.
    ///
    /// Measured as a distance from each neighbour *forwards around the circle*,
    /// which is what makes the pair that straddles zero work: magenta sits at
    /// 320° and red at 0°, and a hue of 350° is 30° past the one and 10° short
    /// of the other, not 330° from it.
    ///
    /// The distance is signed, and that is half the trick. Wrapped into
    /// `0..<360` instead, a band on the far side of the circle reads as a long
    /// way *towards* the hue rather than away from it, and every band ends up
    /// claiming the pixel at full strength.
    ///
    /// The share then eases in and out rather than ramping straight. A ramped
    /// window switches on with a sudden slope, and along a colour transition —
    /// a petal against a leaf, whose pixels sweep through every band on the way
    /// — that is a row of pixels going from untouched to half-darkened between
    /// one pixel and the next. The eye reads that as an outline traced round the
    /// subject, which is exactly what it is. Easing it costs nothing and keeps
    /// the two bands adding up to one: `ease(x) + ease(1 - x)` is one for a
    /// smoothstep, whatever `x` is.
    static func weight(of band: ColorBand, at degrees: Double) -> Double {
        let rising = signed(degrees - band.previous.centre) / band.leftWidth
        let falling = signed(band.next.centre - degrees) / band.rightWidth
        let ramp = min(max(min(rising, falling), 0), 1)
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// `degrees` as a signed distance around the circle, in `-180...180`.
    static func signed(_ degrees: Double) -> Double {
        let wrapped = wrapped(degrees)
        return wrapped > 180 ? wrapped - 360 : wrapped
    }

    /// `degrees` brought into `0..<360`.
    static func wrapped(_ degrees: Double) -> Double {
        let turn = 360.0
        return degrees - turn * (degrees / turn).rounded(.down)
    }

    /// `ColorBand` is written into a recipe under its own name, so a stored
    /// recipe reads as the panel does.
    var codingKey: CodingKey { ColorBandKey(stringValue: rawValue) }

    init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// The key a band is stored under.
///
/// `Dictionary` encodes itself as a keyed container for a key that can say what
/// its coding key is, which turns a recipe into `{"yellow": …}` rather than a
/// list of alternating names and values.
private struct ColorBandKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Which of the three things a band's slider changes.
///
/// The mode the panel's picker is on. All eight bands carry a value in each of
/// the three, which is why switching modes never loses what was set in the one
/// before.
nonisolated enum HSLChannel: String, CaseIterable, Equatable, Sendable, Codable {
    case hue
    case saturation
    case luminance
}

/// What one band's three sliders are set to.
///
/// Normalized like a crop rect rather than kept in the panel's units: the
/// pipeline works in gains and fractions, the panel draws percentages, and the
/// multiplication between them happens in one place instead of everywhere.
nonisolated struct ColorBandShift: Equatable, Sendable, Codable {
    var hue = 0.0
    var saturation = 0.0
    var luminance = 0.0

    /// Whether this band asks for nothing, which is what lets a shot-at-neutral
    /// recipe stay the whole of the file's pixels.
    var isNeutral: Bool { hue == 0 && saturation == 0 && luminance == 0 }

    subscript(channel: HSLChannel) -> Double {
        get {
            switch channel {
            case .hue: hue
            case .saturation: saturation
            case .luminance: luminance
            }
        }
        set {
            switch channel {
            case .hue: hue = newValue
            case .saturation: saturation = newValue
            case .luminance: luminance = newValue
            }
        }
    }
}

/// Everything the colour tool has been told to do.
///
/// Held apart from ``Crop`` because the two are different kinds of edit — one
/// decides which pixels are kept, the other what they look like — and because
/// the panel opens and closes over them separately.
nonisolated struct ColorAdjustments: Equatable, Sendable, Codable {
    /// Every colour at once, and the one slider that can only ever take away.
    var saturation = 0.0
    var vibrance = 0.0

    /// How much of the photo's own cast to neutralise. Unidirectional: there is
    /// no such thing as adding a cast on purpose from a slider called
    /// "Remove Color Cast".
    var colorCast = 0.0

    /// The per-band values, by band. Absent means neutral.
    ///
    /// Sparse rather than eight zeroed entries: a recipe for a photo that had
    /// one band touched should read as one band touched.
    var bands: [ColorBand: ColorBandShift] = [:]

    /// The photo with nothing done to its colours.
    static let identity = ColorAdjustments()

    /// What the bipolar sliders run over, and rest at.
    static let range: ClosedRange<Double> = -1...1

    /// What the cast slider runs over. Zero is off, which is why it is not
    /// ``range``.
    static let colorCastRange: ClosedRange<Double> = 0...1

    /// Whether this asks for the file's own colours.
    var isIdentity: Bool {
        saturation == 0 && vibrance == 0 && colorCast == 0 && !hasBandShift
    }

    /// Whether any band asks for anything, which is what the kernel is for.
    ///
    /// Asked of the values rather than of the dictionary: a decoded recipe can
    /// hold an entry that says nothing, and that should not cost a render pass.
    var hasBandShift: Bool {
        bands.values.contains { !$0.isNeutral }
    }

    /// One band's value in one mode.
    ///
    /// A band that has never been touched reads as zero without being there,
    /// which is what makes the panel's bindings a two-line affair.
    subscript(_ channel: HSLChannel, in band: ColorBand) -> Double {
        get { bands[band]?[channel] ?? 0 }
        set {
            var shift = bands[band] ?? ColorBandShift()
            shift[channel] = newValue
            // Written back or dropped, never left behind: a band that has been
            // returned to neutral has to stop counting as an edit.
            bands[band] = shift.isNeutral ? nil : shift
        }
    }
}
