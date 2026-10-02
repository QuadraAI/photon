//
//  RenderPacing.swift
//  Photon
//

import Foundation

/// How often the canvas is allowed to render.
///
/// A drag reports values faster than a screen takes frames: the pointer has its
/// own rate, the display has sixty or a hundred and twenty a second, and a
/// canvas that rendered every value a slider was handed would spend most of its
/// work on pictures the screen was never going to show. Each of those is a
/// scale, a filter chain and a draw on the GPU, plus a publish on the main
/// actor — and all of it lands while the user is dragging, which is exactly when
/// the picture has to keep up with the pointer.
///
/// So a render is only started once an interval of `1 / (2 × refreshRate)` has
/// passed since the last one began: two display frames' worth, which leaves the
/// second frame for the render's own work to land in.
///
/// A value inside the interval is not dropped. The request is remembered, and
/// the render that follows reads the recipe when it starts rather than when it
/// was asked for, so what lands is the value that arrived last instead of the
/// one that happened to be drawn.
///
/// Stated apart from the view model, in the shape of
/// ``StagedPhotoView/isWorthDrawing(_:at:after:drawnAt:)``, because it is a
/// decision about a clock rather than about a photo: kept here, it can be held
/// to without a screen.
nonisolated enum RenderPacing {
    /// How long the canvas waits between one render and the next: two frames.
    ///
    /// Two rather than one, because a value staged on the display's own tick has
    /// already missed the frame it was for — what is left of that frame is not
    /// enough to scale, filter and draw the picture in — so the render aims at
    /// the frame after it.
    ///
    /// A rate that is not a rate is no cadence at all rather than a canvas that
    /// never draws: the fallback is the wrong way round otherwise, and a screen
    /// that would not say how fast it is must not be the thing that stops the
    /// picture following the pointer.
    static func interval(refreshRate: Double) -> Duration {
        guard refreshRate > 0 else { return .zero }
        return .seconds(1 / (2 * refreshRate))
    }

    /// Whether a render asked for at `now` is worth starting.
    ///
    /// The first render is never held back: there is nothing on the canvas yet,
    /// and holding the first picture back for a cadence that has not begun would
    /// be a window that opens empty.
    ///
    /// - Parameters:
    ///   - now: When the render is being asked for.
    ///   - lastRendered: When the last render began, or nil if there has not
    ///     been one.
    ///   - refreshRate: How many frames a second the display takes, as
    ///     ``AppLayout/displayRefreshRate`` reads it.
    static func shouldRender(
        now: ContinuousClock.Instant,
        lastRendered: ContinuousClock.Instant?,
        refreshRate: Double
    ) -> Bool {
        guard let lastRendered else { return true }
        return now - lastRendered >= interval(refreshRate: refreshRate)
    }
}
