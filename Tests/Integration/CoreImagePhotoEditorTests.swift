//
//  CoreImagePhotoEditorTests.swift
//  PhotonTests
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Photon

/// The engine, against real files.
///
/// Sizes alone catch most of what can go wrong here — a normalized rect read as
/// pixels is off by the frame's aspect every time, and a crop that forgot to move
/// back to the origin comes back the size of the whole photo. But a crop can also
/// be the right size and the wrong *place*, and the only way to see that is to
/// look at the pixels. The fixtures are flat colour swatches, deliberately, so
/// these write their own four-coloured one rather than change what the UI tests
/// are built on.
@Suite("Core Image photo editor")
struct CoreImagePhotoEditorTests {
    private let editor = CoreImagePhotoEditor()

    /// `alpha.png`: 64×48, so 4:3 and every size below comes out whole.
    private var landscape: URL { Self.fixture("alpha.png") }

    /// `beta.png`: 48×64, the same photo the other way up.
    private var portrait: URL { Self.fixture("beta.png") }

    /// `gamma.png`: 32×32, where a ratio has nothing to decide.
    private var square: URL { Self.fixture("Subfolder/gamma.png") }

    // MARK: - Identity

    @Test("A photo with nothing done to it comes back at the size it was asked for")
    func identityRendersThePhoto() async throws {
        let image = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)

        #expect(image.width == 64)
        #expect(image.height == 48)
    }

    @Test("A small photo is not enlarged to the preview size")
    func identityDoesNotUpscale() async throws {
        let image = try await editor.render(landscape, recipe: .identity, maxPixelSize: nil)

        #expect(image.width == 64, "The preview and the export are the same photo at its own size")
        #expect(image.height == 48)
    }

    @Test("The reported size is the photo's own, upright")
    func reportingTheSize() async throws {
        #expect(try await editor.pixelSize(of: landscape) == CGSize(width: 64, height: 48))
        #expect(try await editor.pixelSize(of: portrait) == CGSize(width: 48, height: 64))
        #expect(try await editor.pixelSize(of: square) == CGSize(width: 32, height: 32))
    }

    @Test("A file that is not an image cannot be rendered, and says so")
    func unreadableFilesThrow() async {
        let missing = Self.fixture("does-not-exist.png")

        await #expect(throws: PhotoRenderError.unreadable) {
            try await editor.render(missing, recipe: .identity, maxPixelSize: 512)
        }
        await #expect(throws: PhotoRenderError.unreadable) {
            _ = try await editor.pixelSize(of: missing)
        }
    }

    // MARK: - Cropping

    @Test("A full-frame 16:9 crop takes the pixels the ratio asks for")
    func croppingToARatio() async throws {
        let rect = CropGeometry.fitted(.fixed(width: 16, height: 9), inside: CropGeometry.unitFrame, frame: CGSize(width: 64, height: 48))
        let image = try await editor.render(
            landscape,
            recipe: EditRecipe(crop: Crop(rect: rect, aspect: .fixed(width: 16, height: 9), rotation: .none)),
            maxPixelSize: 2048
        )

        #expect(image.width == 64)
        #expect(image.height == 36)
    }

    @Test("The same recipe gives the same photo at preview size and at full size")
    func previewAndExportAgree() async throws {
        // The whole reason a crop is stored normalized rather than in pixels.
        let crop = Crop(
            rect: CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75),
            aspect: .free,
            rotation: .none
        )
        let recipe = EditRecipe(crop: crop)

        let preview = try await editor.render(landscape, recipe: recipe, maxPixelSize: 2048)
        let full = try await editor.render(landscape, recipe: recipe, maxPixelSize: nil)

        #expect(preview.width == full.width)
        #expect(preview.height == full.height)
        #expect(preview.width == 32)
        #expect(preview.height == 36)
    }

    @Test("A square photo's own ratio is square")
    func aSquarePhotoIsSquare() async throws {
        let rect = CropGeometry.fitted(.original, inside: CropGeometry.unitFrame, frame: CGSize(width: 32, height: 32))
        let image = try await editor.render(
            square,
            recipe: EditRecipe(crop: Crop(rect: rect, aspect: .original, rotation: .none)),
            maxPixelSize: 2048
        )

        #expect(image.width == 32)
        #expect(image.height == 32)
    }

    @Test("Turning the photo swaps which side is the width")
    func turningThePhoto() async throws {
        let recipe = EditRecipe(
            crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .clockwise)
        )
        let image = try await editor.render(landscape, recipe: recipe, maxPixelSize: 2048)

        #expect(image.width == 48)
        #expect(image.height == 64)
    }

    @Test("A quarter turn twice is the photo the right way up, for the pixels")
    func turningTwiceIsThePhotoAgain() async throws {
        let flat = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)
        let twice = try await editor.render(
            landscape,
            recipe: EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .upsideDown)),
            maxPixelSize: 2048
        )

        #expect(twice.width == flat.width)
        #expect(twice.height == flat.height)
        #expect(try bytes(of: twice) == (try bytes(of: flat)))
    }

    // MARK: - Where the crop lands

    @Test("A crop takes the corner it names, on both axes")
    func croppingLandsOnTheRightPixels() async throws {
        // The one thing a size cannot show. Top-left in the recipe means top-left
        // on screen, which means the y flip into Core Image's coordinates
        // happened exactly once.
        let file = try Self.writeQuadrants()
        defer { try? FileManager.default.removeItem(at: file) }

        let frame = CGSize(width: 16, height: 8)
        let corners: [(name: String, rect: CGRect, isExpected: ([UInt8]) -> Bool)] = [
            ("top-left", CGRect(x: 0, y: 0, width: 0.5, height: 0.5), Self.isRed),
            ("top-right", CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), Self.isGreen),
            ("bottom-left", CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), Self.isBlue),
            ("bottom-right", CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), Self.isYellow),
        ]

        for corner in corners {
            let recipe = EditRecipe(crop: Crop(rect: corner.rect, aspect: .free, rotation: .none))
            let image = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

            #expect(image.width == 8, "\(corner.name): the quarter is a quarter")
            #expect(image.height == 4)

            let pixel = try firstPixel(of: image)
            #expect(corner.isExpected(pixel), "\(corner.name) came back as \(pixel)")
        }

        #expect(CropGeometry.pixelRect(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), in: frame).width == 8)
    }

    @Test("Turning moves the region with the pixels, so a crop of a turned photo still finds it")
    func croppingAfterATurn() async throws {
        let file = try Self.writeQuadrants()
        defer { try? FileManager.default.removeItem(at: file) }

        // The top-left quarter, turned a quarter clockwise: it lands top-right.
        let recipe = EditRecipe(
            crop: Crop(
                rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                aspect: .free,
                rotation: .clockwise
            )
        )
        let image = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

        #expect(image.width == 4)
        #expect(image.height == 8)
        #expect(Self.isRed(try firstPixel(of: image)), "The red corner followed the turn")
    }

    // MARK: - The draft

    @Test("A draft comes back, and a later render of the same size can build on it")
    func draftsAreDecoded() async throws {
        let draft = try await editor.draft(for: landscape, maxPixelSize: 2048)

        #expect(draft.width == 64)
        #expect(draft.height == 48)

        let rendered = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)
        #expect(rendered.width == draft.width)
    }

    @Test("A draft of a file that is not an image says so rather than returning nothing")
    func draftsOfUnreadableFilesThrow() async {
        await #expect(throws: PhotoRenderError.unreadable) {
            try await editor.draft(for: Self.fixture("does-not-exist.png"), maxPixelSize: 512)
        }
    }

    // MARK: - Formats

    @Test("A TIFF decodes, reports its size, and crops like any other photo")
    func tiffIsAnImageLikeAnyOther() async throws {
        // A scanner's format and a photographer's export. Neither the size nor the
        // crop cared what container the pixels arrived in.
        let file = try Self.writeQuadrants(as: .tiff)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try await editor.pixelSize(of: file) == CGSize(width: 16, height: 8))

        let full = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        #expect(full.width == 16)
        #expect(full.height == 8)

        // And a crop of it lands on the corner it names, so this is the whole
        // pipeline and not just a decode.
        let recipe = EditRecipe(
            crop: Crop(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), aspect: .free, rotation: .none)
        )
        let corner = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

        #expect(corner.width == 8)
        #expect(corner.height == 4)
        #expect(Self.isGreen(try firstPixel(of: corner)))
    }

    // MARK: - Colour

    @Test("The colour kernel builds on a machine that has Metal")
    func theColourKernelBuilds() {
        // The bands are the one stage the app compiles for itself, and a kernel
        // that failed to build would leave eight sliders moving nothing while
        // the three global ones carried on. Nothing else would say so.
        #expect(ColorKernel.make() != nil)
    }

    @Test("A band's slider moves its own colour and leaves every other colour alone")
    func aBandMovesOnlyItsOwnColours() async throws {
        // The primaries around a cyan that has room to move, so the patch the
        // slider is aimed at changes and the six that are nowhere near it do
        // not. The second half of that is the load-bearing one: it is what holds
        // the kernel's linear-to-sRGB conversion to its inverse.
        let file = try Self.writePatches([
            Self.red, Self.yellow, Self.green, Self.mutedCyan, Self.blue, Self.magenta, Self.white,
        ])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)

        var adjustments = ColorAdjustments()
        adjustments[.saturation, in: .cyan] = 0.5
        let shifted = try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: adjustments),
            maxPixelSize: 2048
        )

        let before = try pixels(of: flat)
        let after = try pixels(of: shifted)

        #expect(after.count == before.count)
        #expect(after[3] != before[3], "Cyan is the colour the cyan slider is for")
        for index in [0, 1, 2, 4, 5, 6] {
            #expect(after[index] == before[index], "Patch \(index) is nowhere near cyan and should not have moved")
        }
    }

    @Test("A band's saturation slider takes colour out of its own colour")
    func aBandsSaturationMovesItsColour() async throws {
        // A yellow and a cyan that are neither fully saturated nor grey, so the
        // slider has somewhere to go in both directions.
        let file = try Self.writePatches([(204, 204, 102), (102, 204, 204)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)

        var raised = ColorAdjustments()
        raised[.saturation, in: .yellow] = 0.39
        let stronger = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: raised), maxPixelSize: 2048)

        var lowered = ColorAdjustments()
        lowered[.saturation, in: .yellow] = -1
        let grey = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: lowered), maxPixelSize: 2048)

        let before = try pixels(of: flat)
        let after = try pixels(of: stronger)

        #expect(
            Self.saturation(of: after[0]) > Self.saturation(of: before[0]),
            "Yellow saturation did not make the yellow more yellow"
        )
        #expect(after[1] == before[1], "The cyan is not the yellow, and should not have moved")

        #expect(
            Self.saturation(of: try pixels(of: grey)[0]) < 0.01,
            "Yellow saturation all the way down left colour in the yellow"
        )
    }

    @Test("A band's hue slider moves its colour toward the next one round the circle")
    func aBandsHueMovesItsColour() async throws {
        // Orange, sitting between red and yellow: a full slider should walk it a
        // third of the way to yellow, which shows up as green arriving.
        let file = try Self.writePatches([(204, 102, 0)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)

        var adjustments = ColorAdjustments()
        adjustments[.hue, in: .orange] = 1
        let shifted = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: adjustments), maxPixelSize: 2048)

        let before = try pixels(of: flat)
        let after = try pixels(of: shifted)

        #expect(after[0][1] > before[0][1] + 20, "A hue shift toward yellow left the green where it was")
        #expect(after[0][2] == 0, "Orange has no blue in it and a hue shift is not going to give it one")
    }

    @Test("A band's luminance slider moves its colour toward white, or toward black")
    func aBandsLuminanceMovesItsColour() async throws {
        let file = try Self.writePatches([(204, 204, 102)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)

        var up = ColorAdjustments()
        up[.luminance, in: .yellow] = 0.5
        let brighter = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: up), maxPixelSize: 2048)

        var down = ColorAdjustments()
        down[.luminance, in: .yellow] = -0.5
        let darker = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: down), maxPixelSize: 2048)

        let before = try pixels(of: flat)
        #expect(try pixels(of: brighter)[0][0] > before[0][0], "Luminance up did not lighten the yellow")
        #expect(try pixels(of: darker)[0][0] < before[0][0], "Luminance down did not darken the yellow")
    }

    @Test("Saturation at its ends greys the photo, and the cast slider neutralises a warm one")
    func theGlobalColourSliders() async throws {
        // A warm, unsaturated patch: something for both sliders to act on.
        let file = try Self.writePatches([(204, 170, 140)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        let before = try pixels(of: flat)
        #expect(Self.saturation(of: before[0]) > 0.2, "This fixture is supposed to have colour in it")

        var drained = ColorAdjustments()
        drained.saturation = -1
        let grey = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: drained), maxPixelSize: 2048)
        #expect(Self.saturation(of: try pixels(of: grey)[0]) < 0.01, "Saturation at -1 did not take the colour out")

        var cast = ColorAdjustments()
        cast.colorCast = 1
        let balanced = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: cast), maxPixelSize: 2048)
        let pixel = try pixels(of: balanced)[0]

        #expect(
            abs(Int(pixel[0]) - Int(pixel[2])) <= 2,
            "Removing the cast left the warm patch reading \(pixel)"
        )
    }

    @Test("Vibrance lifts a muted colour without touching one that is already strong")
    func theVibranceSlider() async throws {
        let file = try Self.writePatches([(150, 120, 120), (255, 0, 0)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)

        var adjustments = ColorAdjustments()
        adjustments.vibrance = 1
        let lifted = try await editor.render(file, recipe: EditRecipe(crop: .identity, color: adjustments), maxPixelSize: 2048)

        let before = try pixels(of: flat)
        let after = try pixels(of: lifted)

        #expect(
            Self.saturation(of: after[0]) > Self.saturation(of: before[0]),
            "Vibrance did nothing for the muted patch"
        )
        #expect(after[1] == before[1], "A colour already at full strength is what vibrance is meant to leave alone")
    }

    @Test("The same colour recipe gives the same photo at preview size and at full size")
    func colourPreviewAndExportAgree() async throws {
        // Including the cast, which is measured rather than computed from the
        // recipe: if the measurement were taken from whatever size the render
        // happened to be working at, the preview and the export would disagree.
        let file = try Self.writePatches([(204, 170, 140), (40, 90, 160)])
        defer { try? FileManager.default.removeItem(at: file) }

        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.4
        adjustments.colorCast = 0.6
        adjustments[.luminance, in: .blue] = -0.3
        let recipe = EditRecipe(crop: .identity, color: adjustments)

        let preview = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)
        let full = try await editor.render(file, recipe: recipe, maxPixelSize: nil)

        #expect(preview.width == full.width)
        #expect(preview.height == full.height)
        #expect(try bytes(of: preview) == (try bytes(of: full)))
    }

    @Test("Every hue is moved by the band the model says owns it, and by that much")
    func theBandsPartitionTheHueCircle() async throws {
        // The test that was missing. The model's arithmetic is unit-tested, and
        // the kernel has a *second* copy of it written into Metal — and that copy
        // had the flanks of red and magenta measured the wrong way round the
        // circle, which left red acting on nothing, magenta acting on everything
        // warm, and cyan and blue each acting at full strength where they met.
        //
        // A sweep of the whole circle, one degree a pixel, compared band by band
        // against what the model says each hue owes to each band.
        let file = try Self.writeHueSweep()
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        // The hue the file actually stores, which is what the kernel sees: a
        // whole degree is not a whole number of eight-bit steps.
        let hues = try pixels(of: flat).map(Self.hue(of:))

        for band in ColorBand.allCases {
            var adjustments = ColorAdjustments()
            adjustments[.hue, in: band] = 1
            let shifted = try await editor.render(
                file,
                recipe: EditRecipe(crop: .identity, color: adjustments),
                maxPixelSize: 2048
            )
            let moved = try pixels(of: shifted).map(Self.hue(of:))

            for (index, hue) in hues.enumerated() {
                let expected = Self.hueShiftDegrees * ColorBand.weight(of: band, at: hue)
                // Below a few degrees a shift is inside what eight bits can
                // resolve, and asserting on it would be asserting on rounding.
                guard expected >= 3 else { continue }

                let actual = Self.shortestShift(from: hue, to: moved[index])
                #expect(
                    abs(actual - expected) <= 3,
                    "\(band.rawValue) at \(hue)°: the model asks for \(expected)° and the kernel moved it \(actual)°"
                )
            }
        }
    }

    @Test("Every band at once moves every hue by the whole slider, and by no more")
    func theBandsAddUpToOne() async throws {
        // The partition of unity, measured through the shader rather than in the
        // model: with all eight sliders at the same value, every hue must move by
        // that value's worth and nothing else. A band that overreaches shows up
        // here as a hue that moved too far, and a band that goes missing as one
        // that did not move at all.
        let file = try Self.writeHueSweep()
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        let hues = try pixels(of: flat).map(Self.hue(of:))

        var adjustments = ColorAdjustments()
        for band in ColorBand.allCases {
            adjustments[.hue, in: band] = 1
        }
        let shifted = try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: adjustments),
            maxPixelSize: 2048
        )
        let moved = try pixels(of: shifted).map(Self.hue(of:))

        for (index, hue) in hues.enumerated() {
            let actual = Self.shortestShift(from: hue, to: moved[index])
            #expect(
                abs(actual - Self.hueShiftDegrees) <= 3,
                "\(hue)° moved \(actual)° with every band at full, not \(Self.hueShiftDegrees)°"
            )
        }
    }

    @Test("A grey has no hue for a band to own")
    func neutralsAreNoBands() async throws {
        // A grey's hue is whatever the last rounding error left behind, and it
        // lands in the red band. Every neutral in a photo was therefore answering
        // to red at full strength, and every anti-aliased edge — where the pixels
        // between two colours are desaturated — was traced with whatever red had
        // been told to do. On a photograph that reads as the tool misbehaving
        // rather than as a slider being strong.
        let file = try Self.writePatches([(128, 128, 128), (132, 128, 124)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try pixels(of: try await editor.render(file, recipe: .identity, maxPixelSize: 2048))

        var everything = ColorAdjustments()
        for band in ColorBand.allCases {
            everything[.hue, in: band] = 1
            everything[.saturation, in: band] = 1
            everything[.luminance, in: band] = 1
        }
        let graded = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: everything),
            maxPixelSize: 2048
        ))

        for channel in 0..<3 {
            #expect(
                abs(Int(graded[0][channel]) - Int(flat[0][channel])) <= 2,
                "A grey came back \(graded[0]) where it was \(flat[0])"
            )
        }

        let moved = zip(graded[1], flat[1]).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
        #expect(
            moved < 30,
            "A colour six per cent of the way out of grey moved by \(moved) with every band at full"
        )
    }

    @Test("Luminance lightens a colour that has no room left in its value")
    func luminanceMovesTheColourRatherThanItsValue() async throws {
        // Pure blue and pure cyan: saturated, so the HSV value of both is already
        // 1. Moving *that* is a slider that can only ever darken them — and that
        // whites out anything less than pure the moment it is touched.
        let file = try Self.writePatches([(0, 0, 255), (0, 255, 255)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        let before = try pixels(of: flat)

        var up = ColorAdjustments()
        up[.luminance, in: .blue] = 1
        let brighter = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: up),
            maxPixelSize: 2048
        ))

        #expect(Self.mean(of: brighter[0]) > Self.mean(of: before[0]) + 60, "Luminance up did not lighten a saturated blue")
        #expect(
            abs(Self.shortestShift(from: Self.hue(of: before[0]), to: Self.hue(of: brighter[0]))) < 4,
            "Lightening the blue moved its hue"
        )
        #expect(brighter[1] == before[1], "The cyan is not the blue and should not have moved")

        var down = ColorAdjustments()
        down[.luminance, in: .blue] = -1
        let darker = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: down),
            maxPixelSize: 2048
        ))

        #expect(Self.mean(of: darker[0]) < Self.mean(of: before[0]) - 30, "Luminance down did not darken it")
        #expect(abs(Self.shortestShift(from: Self.hue(of: before[0]), to: Self.hue(of: darker[0]))) < 4)
    }

    @Test("A colour another band turned yellow is yellow's to adjust")
    func theBandsFollowTheColourAfterAHueShift() async throws {
        // The case that reads as yellow being "too conservative": orange's hue at
        // full turns an orange yellow, and the yellow slider then had nothing to
        // say about it — the colour was still counted as orange, because bands
        // were decided once, from the hue the pixel arrived with.
        //
        // A muted orange, so there is saturation to gain once it is yellow.
        let file = try Self.writePatches([(204, 153, 102)])
        defer { try? FileManager.default.removeItem(at: file) }

        var moved = ColorAdjustments()
        moved[.hue, in: .orange] = 1
        let yellowed = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: moved),
            maxPixelSize: 2048
        ))

        #expect(
            abs(Self.hue(of: yellowed[0]) - 60) < 4,
            "Orange's hue at full left the colour at \(Self.hue(of: yellowed[0]))°, not yellow"
        )

        // And it is yellow's now.
        var both = moved
        both[.saturation, in: .yellow] = 0.5
        let richer = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: both),
            maxPixelSize: 2048
        ))

        #expect(
            Self.saturation(of: richer[0]) > Self.saturation(of: yellowed[0]) + 0.1,
            "Yellow's saturation did nothing for a colour orange had already turned yellow"
        )
    }

    @Test("Two bands cannot both shift the same pixel")
    func theHueShiftIsNotAppliedTwice() async throws {
        // Which band moves a pixel is asked of the colour as it *arrived*, or a
        // colour that orange had just moved into yellow would be moved again by
        // yellow's own hue slider, and the shift would depend on the order the
        // bands were read in. Orange at full is 30°, and that is all it may be.
        let file = try Self.writePatches([(204, 153, 102)])
        defer { try? FileManager.default.removeItem(at: file) }

        let flat = try pixels(of: try await editor.render(file, recipe: .identity, maxPixelSize: 2048))

        var both = ColorAdjustments()
        both[.hue, in: .orange] = 1
        both[.hue, in: .yellow] = 1
        let shifted = try pixels(of: try await editor.render(
            file,
            recipe: EditRecipe(crop: .identity, color: both),
            maxPixelSize: 2048
        ))

        // 30° from orange, and nothing on top: the colour was orange when it
        // arrived, so yellow had no share of it.
        let moved = Self.shortestShift(from: Self.hue(of: flat[0]), to: Self.hue(of: shifted[0]))

        #expect(abs(moved - 30) < 4, "Orange plus yellow moved the colour \(moved)° rather than 30°")
    }

    @Test("A file that is not a RAW is not put through the RAW pipeline")
    func ordinaryFilesAreNotRaw() {
        // The decode branches on what Core Image says the file is rather than on
        // its extension, so this is the assumption that keeps every other test in
        // this file on the path it was written for. A RAW fixture cannot be
        // committed — a camera file is tens of megabytes — so what is pinned here
        // is the near side of the branch.
        for name in ["alpha.png", "beta.png", "Subfolder/delta.jpg"] {
            #expect(
                CIFilter(imageURL: Self.fixture(name), options: nil) as? CIRAWFilter == nil,
                "\(name) was taken for a RAW"
            )
        }
    }

    // MARK: - Helpers

    /// A fixture from `Tests/Photos`, addressed as a plain filesystem path.
    private static func fixture(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Photos")
            .appending(path: name)
    }

    // MARK: - A photo whose colours can be told apart

    /// A flat colour, as sRGB bytes.
    private typealias Patch = (r: UInt8, g: UInt8, b: UInt8)

    /// The colours the colour tests are written against.
    ///
    /// The primaries and white are 0 or 255 in every channel, which is what makes
    /// them worth using: they are the colours a trip through Core Image — decode,
    /// linear working space, kernel, encode — can be held to *exactly*. An
    /// untouched patch has nowhere to drift to, so a patch that moved is a patch
    /// the maths moved.
    private static let red: Patch = (255, 0, 0)
    private static let yellow: Patch = (255, 255, 0)
    private static let green: Patch = (0, 255, 0)
    private static let blue: Patch = (0, 0, 255)
    private static let magenta: Patch = (255, 0, 255)
    private static let white: Patch = (255, 255, 255)

    /// A cyan that is holding something back.
    ///
    /// A pure cyan is already as saturated as a colour gets, so "more cyan" has
    /// nothing left to add to it, and a slider aimed at it would look broken
    /// while working perfectly.
    private static let mutedCyan: Patch = (102, 204, 204)

    /// Writes a one-row picture of flat colours.
    ///
    /// One row rather than a grid, so there is no orientation to get wrong: the
    /// patches come back in the order they went in, which is what lets an
    /// assertion name one by index.
    private static func writePatches(_ patches: [Patch]) throws -> URL {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: patches.count,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: patches.count * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw FixtureError.couldNotBuildTheFile }

        for (index, patch) in patches.enumerated() {
            context.setFillColor(
                CGColor(
                    srgbRed: CGFloat(patch.r) / 255,
                    green: CGFloat(patch.g) / 255,
                    blue: CGFloat(patch.b) / 255,
                    alpha: 1
                )
            )
            context.fill(CGRect(x: index, y: 0, width: 1, height: 1))
        }

        guard let image = context.makeImage() else { throw FixtureError.couldNotBuildTheFile }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "photon-colour-test-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw FixtureError.couldNotBuildTheFile }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.couldNotBuildTheFile }

        return url
    }

    /// Every pixel's red, green and blue, in the order the picture is drawn.
    private func pixels(of image: CGImage) throws -> [[UInt8]] {
        let all = try bytes(of: image)
        return stride(from: 0, to: all.count - 3, by: 4).map { Array(all[$0..<($0 + 3)]) }
    }

    /// How far a full slider moves a hue, in degrees.
    ///
    /// The same figure the kernel is generated with, so this is what the test is
    /// holding the two implementations to between them.
    private static let hueShiftDegrees = 30.0

    /// A one-row picture that walks the hue circle, one degree a pixel.
    private static func writeHueSweep() throws -> URL {
        try writePatches((0..<360).map { patch(hue: Double($0)) })
    }

    /// A fully saturated, full-value colour of `hue` degrees, as sRGB bytes.
    private static func patch(hue degrees: Double) -> Patch {
        let sector = wrapped(degrees) / 60
        let index = Int(sector.rounded(.down))
        let f = sector - Double(index)
        let q = 1 - f
        let t = f

        let (r, g, b): (Double, Double, Double) = switch index {
        case 0: (1, t, 0)
        case 1: (q, 1, 0)
        case 2: (0, 1, t)
        case 3: (0, q, 1)
        case 4: (t, 0, 1)
        default: (1, 0, q)
        }

        return (
            UInt8((r * 255).rounded()),
            UInt8((g * 255).rounded()),
            UInt8((b * 255).rounded())
        )
    }

    /// A pixel's hue in degrees. Grey has none, and reads as red.
    private static func hue(of pixel: [UInt8]) -> Double {
        let r = Double(pixel[0]), g = Double(pixel[1]), b = Double(pixel[2])
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let delta = high - low
        guard delta > 0 else { return 0 }

        let sector: Double
        if high == r {
            sector = (g - b) / delta
        } else if high == g {
            sector = 2 + (b - r) / delta
        } else {
            sector = 4 + (r - g) / delta
        }
        return wrapped(sector * 60)
    }

    /// How far `to` is from `from`, the short way round the circle.
    private static func shortestShift(from: Double, to: Double) -> Double {
        let forward = wrapped(to - from)
        return forward > 180 ? forward - 360 : forward
    }

    /// `degrees` brought into `0..<360`.
    private static func wrapped(_ degrees: Double) -> Double {
        let turn = 360.0
        return degrees - turn * (degrees / turn).rounded(.down)
    }

    /// The average of a pixel's three channels, which is enough to see whether a
    /// colour was moved toward white or toward black.
    private static func mean(of pixel: [UInt8]) -> Double {
        Double(pixel.reduce(0) { $0 + Int($1) }) / 3
    }

    /// How much colour a pixel has, the way HSV measures it.
    private static func saturation(of pixel: [UInt8]) -> Double {
        let high = Double(pixel.max() ?? 0)
        let low = Double(pixel.min() ?? 0)
        return high > 0 ? (high - low) / high : 0
    }

    // MARK: - A photo whose corners can be told apart

    private enum FixtureError: Error {
        case couldNotBuildTheFile
        case couldNotReadThePixels
    }

    /// Writes a 16×8 picture of four quadrants — red top-left, green top-right,
    /// blue bottom-left, yellow bottom-right — in `type`'s format.
    ///
    /// Colours named by where they are *seen*, which is the whole point — the
    /// drawing context counts y the other way, so the conversion happens here and
    /// the assertions can be about the picture.
    private static func writeQuadrants(as type: UTType = .png) throws -> URL {
        let size = CGSize(width: 16, height: 8)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw FixtureError.couldNotBuildTheFile }

        /// Fills a rectangle given by its place in the picture.
        func fill(_ colour: CGColor, left: CGFloat, top: CGFloat) {
            context.setFillColor(colour)
            context.fill(
                CGRect(
                    x: left,
                    y: size.height - top - size.height / 2,
                    width: size.width / 2,
                    height: size.height / 2
                )
            )
        }

        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let yellow = CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)

        fill(red, left: 0, top: 0)
        fill(green, left: size.width / 2, top: 0)
        fill(blue, left: 0, top: size.height / 2)
        fill(yellow, left: size.width / 2, top: size.height / 2)

        guard let image = context.makeImage() else { throw FixtureError.couldNotBuildTheFile }

        let suffix = type.preferredFilenameExtension ?? "png"
        let url = FileManager.default.temporaryDirectory
            .appending(path: "photon-editor-test-\(UUID().uuidString).\(suffix)")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { throw FixtureError.couldNotBuildTheFile }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.couldNotBuildTheFile }

        return url
    }

    /// Every pixel of an image, as bytes, so two renders can be compared.
    private func bytes(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)

        try data.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { throw FixtureError.couldNotReadThePixels }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }

    /// The first pixel's red, green and blue.
    private func firstPixel(of image: CGImage) throws -> [UInt8] {
        Array(try bytes(of: image).prefix(3))
    }

    // Predicates rather than exact values: the file round-trips through sRGB, and
    // what is being tested is which corner came back, not the arithmetic of 255.
    private static func isRed(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60 }
    private static func isGreen(_ pixel: [UInt8]) -> Bool { pixel[0] < 60 && pixel[1] > 200 && pixel[2] < 60 }
    private static func isBlue(_ pixel: [UInt8]) -> Bool { pixel[0] < 60 && pixel[1] < 60 && pixel[2] > 200 }
    private static func isYellow(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] > 200 && pixel[2] < 60 }
}
