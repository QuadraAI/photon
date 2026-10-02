//
//  MetalPhotoView.swift
//  Photon
//

import CoreImage
import Metal
import MetalKit
import SwiftUI

/// A staged photo, drawn by the context that staged it.
///
/// The canvas used to show a `CGImage`: the engine rendered on the GPU, waited
/// for it, copied the whole picture back to the CPU, and SwiftUI uploaded it
/// again as a texture — twice a preview's worth of pixels across the bus on
/// every frame of a slider drag. Worse than the copying is the waiting: a
/// `CGImage` is a finished picture, so frame *n*+1 could not begin until frame
/// *n* had been handed over. Apple's guidance for editing one photo repeatedly
/// at screen resolution is to render directly to a Metal-backed view, "because
/// Metal can start work on the next frame before the previous frame is
/// completed", and this is that view.
///
/// It decides nothing: no filters, no geometry, no colour management of its own.
/// The image arrives already staged, and this puts it on the drawable as it is.
struct MetalPhotoView: View {
    let image: CIImage

    /// The context the image was staged with, which is the one that has to draw
    /// it: a second context would compile the same kernels again and have none
    /// of the first one's cached work to build on.
    let context: CIContext

    /// What the picture is announced as, which is the photo's name.
    let label: String

    var body: some View {
        MetalPhotoRepresentable(image: image, context: context, label: label)
    }
}

#if os(macOS)
private struct MetalPhotoRepresentable: NSViewRepresentable {
    let image: CIImage
    let context: CIContext
    let label: String

    func makeNSView(context: Context) -> StagedPhotoView {
        StagedPhotoView(image: image, imageContext: self.context, label: label)
    }

    func updateNSView(_ view: StagedPhotoView, context: Context) {
        view.show(image, label: label)
    }
}
#else
private struct MetalPhotoRepresentable: UIViewRepresentable {
    let image: CIImage
    let context: CIContext
    let label: String

    func makeUIView(context: Context) -> StagedPhotoView {
        StagedPhotoView(image: image, imageContext: self.context, label: label)
    }

    func updateUIView(_ view: StagedPhotoView, context: Context) {
        view.show(image, label: label)
    }
}
#endif

/// The drawable a staged photo is put on.
///
/// An `MTKView` that redraws when it is told to rather than sixty times a
/// second: a photograph that has not changed is not worth a frame, and the
/// engine knows when one has.
final class StagedPhotoView: MTKView {
    private let imageContext: CIContext
    private var image: CIImage?

    /// The picture already on the drawable.
    ///
    /// A frame with nothing new in it is a frame not worth rendering: the view
    /// draws on the display's clock, and most of those ticks arrive between two
    /// slider values rather than on one.
    private var drawn: CIImage?

    /// The queue the frame is presented on.
    ///
    /// The render and the present have to be on one command buffer, or the
    /// drawable is handed to the display before the picture has been put in it.
    private let commandQueue: MTLCommandQueue?

    /// What the canvas is addressed by, for VoiceOver and for the tests.
    static let identifier = "editor.canvas.image"

    /// The colour space the drawable's values are in.
    ///
    /// The canvas draws in the display's own space — a `CAMetalLayer` with no
    /// space of its own is sRGB — and Core Image converts into it from whatever
    /// the engine staged, which is the context's *linear* working space.
    /// Inheriting the picture's own space instead wrote those linear values
    /// straight to the screen, which is the whole photo gone dark.
    private static let outputColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(image: CIImage, imageContext: CIContext, label: String) {
        self.imageContext = imageContext
        self.image = image
        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        super.init(frame: .zero, device: device)

        framebufferOnly = false
        autoResizeDrawable = true
        // Drawn on the display's clock rather than when told to. A slider drag
        // produces values faster than the screen takes frames, and asking for a
        // frame per value puts the main thread on the hook for every one of
        // them — which is the pointer waiting for the picture instead of the
        // picture following the pointer. One frame per display frame coalesces
        // the rest, and a frame with nothing new in it costs a comparison.
        isPaused = false
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false

        // The picture is what is being looked at, so it is announced as one:
        // VoiceOver and the tests both address it by the photo's name.
        #if os(macOS)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        #else
        isAccessibilityElement = true
        accessibilityTraits = .image
        #endif
        setAccessibilityIdentifier(Self.identifier)
        show(image, label: label)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("StagedPhotoView is made in code")
    }

    /// Puts a new picture up, and lets the next frame draw it.
    func show(_ image: CIImage, label: String) {
        self.image = image
        setAccessibilityLabel(label)
    }

    #if os(macOS)
    override func draw(_ dirtyRect: NSRect) { drawPicture() }
    #else
    override func draw(_ rect: CGRect) { drawPicture() }
    #endif

    /// Draws the staged picture into the drawable.
    ///
    /// `startTask` rather than `render`: the task hands the work to the GPU and
    /// comes back, so the next frame can start before this one has finished.
    /// Waiting for a finished picture — which is what asking for pixels does —
    /// is the cost this view exists to avoid.
    private func drawPicture() {
        let extent = image?.extent ?? .zero
        guard let image, image !== drawn, extent.width > 0, extent.height > 0,
              drawableSize.width > 0,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer()
        else { return }

        // Put the picture where its own origin is, then fill the drawable with
        // it. Both steps earn their place: a crop is moved back to the origin and
        // a turn is not, so the extent cannot be assumed to start at nothing.
        let scale = Self.scale(of: image, in: drawableSize)
        let placed = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        Self.draw(
            placed,
            into: drawable.texture,
            bounds: CGRect(origin: .zero, size: drawableSize),
            commandBuffer: commandBuffer,
            with: imageContext
        )
        // Present first, then commit: the drawable goes to the display when the
        // work that fills it is done, and not before.
        commandBuffer.present(drawable)
        commandBuffer.commit()
        drawn = image
    }

    /// Draws a staged picture into a texture, in the space a display reads.
    ///
    /// `render(_:to:commandBuffer:bounds:colorSpace:)` rather than a
    /// `CIRenderDestination`, because here the colour space is stated and is
    /// taken as the space of the *result*: the engine stages its previews in the
    /// context's linear working space, so what goes to the screen has to be
    /// converted out of it. A destination built around a texture left those
    /// linear values as they were — the whole photo gone dark — and this is also
    /// the call Apple's own Core Image and Metal guidance names for the job.
    ///
    /// A function rather than three lines inline, so a test can draw the way the
    /// canvas draws.
    static func draw(
        _ image: CIImage,
        into texture: any MTLTexture,
        bounds: CGRect,
        commandBuffer: (any MTLCommandBuffer)?,
        with context: CIContext
    ) {
        context.render(
            image,
            to: texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: outputColorSpace
        )
    }

    /// How much a staged picture is scaled by to fill the drawable it is drawn in.
    ///
    /// The image is measured in its own pixels and the drawable in device ones,
    /// and the canvas lays this view out at the picture's own shape — so this is
    /// the ratio between *those* two sizes, and not the display's scale. Scaling
    /// by the display's factor draws the preview two or three times the size of
    /// the view that holds it, which shows as a quarter of the photo in a corner.
    static func scale(of image: CIImage, in drawable: CGSize) -> CGFloat {
        let extent = image.extent
        guard extent.width > 0, drawable.width > 0 else { return 1 }
        return drawable.width / extent.width
    }
}
