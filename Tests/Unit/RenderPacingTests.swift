//
//  RenderPacingTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// How often the canvas is allowed to render.
///
/// The decision is one comparison, and getting it wrong is invisible in every
/// way but the one that matters: the canvas shows the right picture, only late,
/// with the pointer ahead of it. A drag that renders every value it is handed
/// spends most of its work on frames the screen never takes.
///
/// Held here, without a screen, because the alternative is a test that measures
/// a stopwatch — and because the measured form of the same claim, that a drag
/// cannot outrun the display, is in ``EditorViewModelTests``.
@Suite("Render pacing")
struct RenderPacingTests {
    @Test("A render inside the interval waits for the screen's next frame")
    func tooSoonIsNotWorthStarting() {
        let began = ContinuousClock.now

        #expect(
            !RenderPacing.shouldRender(now: began + .milliseconds(4), lastRendered: began, refreshRate: 60),
            "Four milliseconds after the last render is inside a 60 Hz display's interval"
        )
    }

    @Test("A render once the interval has passed is worth starting")
    func afterTheIntervalItRenders() {
        let began = ContinuousClock.now

        #expect(
            RenderPacing.shouldRender(now: began + .milliseconds(9), lastRendered: began, refreshRate: 60),
            "Nine milliseconds is past a 60 Hz display's interval"
        )
    }

    @Test("The first render is never held back")
    func theFirstRenderIsNotHeldBack() {
        // Nothing on the canvas yet, so there is no cadence to keep to: a
        // window that opened empty for the length of an interval that has not
        // begun would be a blank editor to look at.
        #expect(RenderPacing.shouldRender(now: .now, lastRendered: nil, refreshRate: 60))
    }

    @Test("The interval is two frames of the display")
    func theIntervalIsTwoFrames() {
        // Two frames and not one: a value staged on the display's own tick has
        // already missed the frame it was for, so the render aims at the one
        // after it.
        #expect(RenderPacing.interval(refreshRate: 100) == .milliseconds(5))
    }

    @Test("A display that refreshes twice as fast halves the interval")
    func aFasterDisplayHalvesTheInterval() {
        // Which is the whole reason the interval is derived from the display
        // rather than fixed: an iPad Pro takes two frames in the time a 60 Hz
        // display takes one, and rendering at the slower rate would leave every
        // second frame with nothing new in it.
        #expect(RenderPacing.interval(refreshRate: 200) * 2 == RenderPacing.interval(refreshRate: 100))
    }

    @Test("A display that will not say how fast it is is not a stopped canvas")
    func aRateThatIsNotARateIsNoCadence() {
        // The fallback has to fail towards drawing rather than towards not
        // drawing: a screen that answers with nothing must not be the thing that
        // stops the picture following the pointer.
        let began = ContinuousClock.now

        #expect(RenderPacing.interval(refreshRate: 0) == .zero)
        #expect(RenderPacing.shouldRender(now: began, lastRendered: began, refreshRate: 0))
    }
}
