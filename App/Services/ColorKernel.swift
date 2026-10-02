//
//  ColorKernel.swift
//  Photon
//

import CoreImage
import Foundation
import os

/// The per-band hue, saturation and luminance maths, as a Metal colour kernel.
///
/// A kernel rather than a colour cube or a chain of eight filters. A cube would
/// mean rebuilding a 32,768-entry table on every slider tick and interpolating
/// between its entries, and eight chained filters could not blend two bands
/// across a hue without eight masks. One kernel is exact, costs nothing per
/// change, and is the same machinery masking, denoise and the detail tools will
/// need.
///
/// The source is compiled at runtime — `CIKernel.kernels(withMetalString:)`
/// takes Metal as a string — so there is no `.metal` file, no `-fcikernel`, no
/// metallib to find in the bundle and no build setting to get wrong. It is
/// compiled once, by ``make()``, and held by the engine.
///
/// The maths runs in gamma-encoded sRGB, converted from the context's linear
/// working space on the way in and back on the way out: a hue angle is a claim
/// about how a colour looks, and in a linear space two colours the eye calls
/// orange sit at wildly different angles.
nonisolated enum ColorKernel {
    /// The Metal function's name, which is also how ``make()`` finds it.
    static let functionName = "colorBands"

    private static let logger = Logger(subsystem: "com.quadra.Photon", category: "ColorKernel")

    // MARK: - Building

    /// Compiles the kernel, or nil on a machine that cannot have one.
    ///
    /// Nil is not fatal: the three global sliders are Core Image's own filters
    /// and keep working, and only the eight bands go quiet. It is worth a log
    /// line rather than a throw, because the reason would be a machine with no
    /// Metal device — and there is nothing the person in front of it could do
    /// about that.
    static func make() -> CIColorKernel? {
        do {
            let kernels = try CIKernel.kernels(withMetalString: source())
            guard let kernel = kernels.first(where: { $0.name == functionName }) as? CIColorKernel else {
                logger.error("The colour kernel came back as something other than a colour kernel")
                return nil
            }
            return kernel
        } catch {
            logger.error("Could not build the colour kernel: \(error.localizedDescription)")
            return nil
        }
    }

    /// The kernel applied to `image`, or nil when Core Image declined the work.
    static func apply(_ adjustments: ColorAdjustments, to image: CIImage, using kernel: CIColorKernel) -> CIImage? {
        kernel.apply(extent: image.extent, arguments: arguments(for: adjustments, image: image))
    }

    /// The kernel's arguments, in the order its function declares them.
    ///
    /// Eight bands do not fit in one vector, so each is passed as a pair of
    /// `float4`s — low half then high half — which is also how the kernel's
    /// generated table is arranged.
    private static func arguments(for adjustments: ColorAdjustments, image: CIImage) -> [Any] {
        func halves(_ channel: HSLChannel) -> [CIVector] {
            let values = ColorBand.allCases.map { adjustments[channel, in: $0] }
            return [vector(values, half: 0), vector(values, half: 1)]
        }

        let hue = halves(.hue)
        let saturation = halves(.saturation)
        let luminance = halves(.luminance)

        return [image, hue[0], hue[1], saturation[0], saturation[1], luminance[0], luminance[1]]
    }

    /// Four values as a `CIVector`, which is how a kernel receives a `float4`.
    private static func vector(_ values: [Double], half: Int) -> CIVector {
        let start = half * 4
        return CIVector(
            x: values[start],
            y: values[start + 1],
            z: values[start + 2],
            w: values[start + 3]
        )
    }

    // MARK: - The program

    /// The Metal program, with the band table written into it.
    ///
    /// The centres are generated from ``ColorBand/centre`` rather than written
    /// out again, so there is one place in the app that decides where yellow is.
    /// Every other number here is a property of the model too — the flanks are
    /// the distances to the neighbouring centres, and the ramp between them is
    /// the rule ``ColorBand/weight(of:at:)`` states in Swift for the tests to
    /// hold.
    static func source() -> String {
        let half = ColorBand.allCases.count / 2
        let low = Array(ColorBand.allCases.prefix(half))
        let high = Array(ColorBand.allCases.suffix(half))

        func literal(_ values: [Double]) -> String {
            "float4(" + values.map { "\($0)" }.joined(separator: ", ") + ")"
        }

        let table = """
            constant float4 kLeftCentreLow = \(literal(low.map(\.previous.centre)));
            constant float4 kLeftCentreHigh = \(literal(high.map(\.previous.centre)));
            constant float4 kLeftWidthLow = \(literal(low.map(\.leftWidth)));
            constant float4 kLeftWidthHigh = \(literal(high.map(\.leftWidth)));
            constant float4 kRightCentreLow = \(literal(low.map(\.next.centre)));
            constant float4 kRightCentreHigh = \(literal(high.map(\.next.centre)));
            constant float4 kRightWidthLow = \(literal(low.map(\.rightWidth)));
            constant float4 kRightWidthHigh = \(literal(high.map(\.rightWidth)));
            """

        return """
        #include <metal_stdlib>
        #include <CoreImage/CoreImage.h>
        using namespace metal;

        // The hue circle's eight bands: where each one sits, and how far it is
        // from the band either side of it. Generated — see ColorKernel.source.
        \(table)

        // A full turn, half of one, and how far a slider at its end moves a hue.
        constant float kTurn = 360.0;
        constant float kHalfTurn = 180.0;
        constant float kHueShiftDegrees = 30.0;

        // How far a luminance slider at its end moves a colour toward white or
        // black, as a fraction of the whole way there. Half, because neither
        // Lightroom nor Luminar reaches the ends at the top of the slider — a
        // colour taken all the way to white is not a colour any more — and
        // because half of the distance is already a strong adjustment.
        constant float kLuminanceReach = 0.5;

        /// Distance around the circle as a signed one, in -180...180.
        ///
        /// Signed because a band on the far side of the circle has to read as a
        /// long way *away* from a hue rather than towards it: wrapped into
        /// 0...360 every band would claim every pixel at full strength.
        inline float4 signed4(float4 degrees) {
            float4 wrapped = degrees - kTurn * floor(degrees / kTurn);
            return select(wrapped - kTurn, wrapped, wrapped <= kHalfTurn);
        }

        /// How much of a hue each band answers for, given its own flanks.
        ///
        /// A partition of unity: the two bands whose centres bracket a hue share
        /// it in proportion to how close it is to each, and the other six are
        /// exactly zero. The Swift model states the same rule — see
        /// `ColorBand.weight(of:at:)` — and the table above is generated from it,
        /// so the two cannot drift apart.
        ///
        /// The share eases in and out rather than ramping straight, because a
        /// ramped window switches on with a slope the eye reads as an outline
        /// drawn round a subject: along a soft edge between two colours, where
        /// the pixels between them sweep through several bands, it drew a line.
        inline float4 bandWeights(float degrees, float4 leftCentre, float4 leftWidth,
                                  float4 rightCentre, float4 rightWidth) {
            float4 hue = float4(degrees);
            float4 ramp = min(saturate(signed4(hue - leftCentre) / leftWidth),
                              saturate(signed4(rightCentre - hue) / rightWidth));
            return smoothstep(0.0, 1.0, ramp);
        }

        /// What the eight bands ask of a pixel of this hue, weighted and summed.
        ///
        /// The eight do not fit in one vector, which is why they arrive in two
        /// halves and why this adds two dots rather than one.
        inline float bandValue(float degrees, float4 low, float4 high) {
            return dot(bandWeights(degrees, kLeftCentreLow, kLeftWidthLow, kRightCentreLow, kRightWidthLow), low)
                + dot(bandWeights(degrees, kLeftCentreHigh, kLeftWidthHigh, kRightCentreHigh, kRightWidthHigh), high);
        }

        /// How much of a band's work a pixel takes, given how colourful it is.
        ///
        /// A near-grey has a hue — whatever the last rounding error left behind —
        /// but not one anybody looks at, and it has no business being graded as
        /// red. Without this every neutral in a photo answers to the red band at
        /// full strength, and every edge where two colours meet, where the pixels
        /// between them are desaturated, comes out traced with whatever that band
        /// was told to do.
        inline float colourfulness(float saturation) {
            return smoothstep(0.02, 0.18, saturation);
        }

        /// Linear to gamma-encoded sRGB.
        ///
        /// Values below zero arrive from a wide-gamut photo in an extended
        /// working space. They are held at zero rather than handed to `pow`,
        /// which would return a NaN and take the whole pixel with it.
        inline float3 encode(float3 linear) {
            float3 x = max(linear, 0.0);
            return select(1.055 * pow(x, 1.0 / 2.4) - 0.055, 12.92 * x, x <= 0.0031308);
        }

        /// Gamma-encoded sRGB back to linear.
        inline float3 decode(float3 gamma) {
            float3 x = max(gamma, 0.0);
            return select(pow((x + 0.055) / 1.055, 2.4), x / 12.92, x <= 0.04045);
        }

        /// RGB as hue, saturation and value, hue in 0...1.
        inline float3 toHSV(float3 c) {
            float high = max(c.r, max(c.g, c.b));
            float low = min(c.r, min(c.g, c.b));
            float delta = high - low;

            float hue = 0.0;
            if (delta > 0.0) {
                if (high == c.r) {
                    hue = (c.g - c.b) / delta;
                } else if (high == c.g) {
                    hue = 2.0 + (c.b - c.r) / delta;
                } else {
                    hue = 4.0 + (c.r - c.g) / delta;
                }
                hue = fract(hue / 6.0 + 1.0);
            }

            return float3(hue, high > 0.0 ? delta / high : 0.0, high);
        }

        /// Hue, saturation and value back to RGB.
        inline float3 toRGB(float3 hsv) {
            float sector = fract(hsv.x) * 6.0;
            float f = sector - floor(sector);
            float p = hsv.z * (1.0 - hsv.y);
            float q = hsv.z * (1.0 - hsv.y * f);
            float t = hsv.z * (1.0 - hsv.y * (1.0 - f));

            switch (int(floor(sector))) {
                case 0: return float3(hsv.z, t, p);
                case 1: return float3(q, hsv.z, p);
                case 2: return float3(p, hsv.z, t);
                case 3: return float3(p, q, hsv.z);
                case 4: return float3(t, p, hsv.z);
                default: return float3(hsv.z, p, q);
            }
        }

        extern "C" {
            namespace coreimage {
                /// One pixel, with the eight bands' three shifts applied.
                ///
                /// The weights are a partition of unity, so the shifts below are
                /// already the answer: no accumulation, no normalising, and a
                /// hue exactly on a band's centre is that band's alone.
                [[stitchable]] float4 \(functionName)(coreimage::sample_t source,
                                                      float4 hueLow, float4 hueHigh,
                                                      float4 saturationLow, float4 saturationHigh,
                                                      float4 luminanceLow, float4 luminanceHigh) {
                    // Core Image hands pixels over premultiplied, and a hue is
                    // not a property of a colour that has been multiplied by its
                    // own alpha.
                    float alpha = source.a;
                    float3 straight = alpha > 0.0 ? source.rgb / alpha : source.rgb;

                    float3 hsv = toHSV(encode(straight));

                    // Which bands move this pixel is a question about the photo,
                    // so it is asked of the colour as it *arrived*, and answered
                    // in proportion to how colourful it is: a grey is no band's.
                    float colourful = colourfulness(hsv.y);
                    float hueShift = bandValue(hsv.x * kTurn, hueLow, hueHigh) * colourful;
                    hsv.x = fract((hsv.x * kTurn + hueShift * kHueShiftDegrees) / kTurn + 1.0);

                    // The other two are asked of the colour as it now *is*: once
                    // orange has been turned yellow, the colour is yellow, and
                    // yellow's sliders are the ones with something to say about
                    // it. Nothing here can move the hue it was just read from, so
                    // one pass settles.
                    float saturationGain = bandValue(hsv.x * kTurn, saturationLow, saturationHigh) * colourful;
                    float luminanceShift = bandValue(hsv.x * kTurn, luminanceLow, luminanceHigh) * colourful;

                    hsv.y = saturate(hsv.y * (1.0 + saturationGain));

                    // Luminance last, and moved on the colour rather than on
                    // HSV's value: a saturated colour's value is already 1, so a
                    // slider that moved it could darken blue but never lighten it.
                    // Adding toward white and scaling toward black moves every
                    // channel by the same affine amount, so the hue comes through
                    // exactly as it was, and a lighter colour is a paler one.
                    float3 lit = toRGB(hsv);
                    float reach = luminanceShift * kLuminanceReach;
                    lit = lit + max(reach, 0.0) * (1.0 - lit) + min(reach, 0.0) * lit;

                    return float4(decode(lit) * alpha, alpha);
                }
            }
        }
        """
    }
}
