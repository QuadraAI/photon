//
//  GradientSlider.swift
//  Photon
//

import SwiftUI

/// A slider drawn as a colour running through its track, in the manner of
/// Luminar's.
///
/// SwiftUI's own `Slider` cannot be asked for a gradient track, and the track is
/// carrying something here: which band a row moves, and which way is more of it.
/// So the control is drawn rather than borrowed — and everything a borrowed
/// control does for free has to be put back by hand. It is one accessibility
/// element, it reports where it is, VoiceOver and Switch Control can adjust it,
/// and the arrow keys move it when it has focus.
///
/// The value it edits is normalized, like everything else a recipe holds. The
/// panel beside it is what says "39" rather than 0.39.
struct GradientSlider: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Where the value is.
    ///
    /// A binding rather than a pair of callbacks so the panel can hand over the
    /// same recipe subscript it reads: a slider that held its own copy would drift
    /// away from what the canvas is showing the moment anything else moved it.
    @Binding var value: Double

    /// What the value runs over.
    let range: ClosedRange<Double>

    /// What "nothing" is: the middle of a bipolar slider, the bottom of one that
    /// only ever takes away.
    let neutral: Double

    /// What fills the track between ``neutral`` and the thumb, and colours the
    /// thumb and its halo.
    let tint: Color

    /// The colours the whole track runs through, left to right.
    ///
    /// Drawn held back, under the fill: it is what the slider *does* rather than
    /// what it has been set to, and the two are read differently on purpose.
    let ramp: [Color]

    /// Spoken as the control's name, so it has to say which slider it is rather
    /// than which row it is on.
    let label: Text

    /// How far one arrow key, or one VoiceOver swipe, moves it.
    let step: Double

    /// What it is addressed by, for the tests that drive it.
    let identifier: String

    /// Called when a drag ends, so the panel can close the change it opened. Not
    /// called for a nudge: a run of those is one change, and the panel closing is
    /// what commits it.
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let radius = AppLayout.colorSliderThumbSize / 2
            // The thumb travels within its own width rather than across the whole
            // control, so at either end it sits *on* the end of the track instead
            // of hanging off the side of it.
            let travel = max(0, width - AppLayout.colorSliderThumbSize)
            let spot = radius + Self.position(of: value, in: range) * travel
            let origin = radius + Self.position(of: neutral, in: range) * travel

            ZStack(alignment: .leading) {
                // The colour across the whole track, held back: it says what the
                // slider does and which way is more of it, and that the right
                // hand end is the end that has more.
                Capsule()
                    .fill(LinearGradient(colors: ramp, startPoint: .leading, endPoint: .trailing))
                    .opacity(0.45)
                    .frame(height: AppLayout.colorSliderTrackHeight)

                // What has been asked for so far, drawn at full strength from
                // where nothing is to where the value is — the same read
                // whichever side of neutral it landed on.
                Capsule()
                    .fill(tint)
                    .frame(width: abs(spot - origin), height: AppLayout.colorSliderTrackHeight)
                    .offset(x: min(spot, origin))

                if !reduceTransparency {
                    Circle()
                        .fill(tint)
                        .opacity(0.3)
                        .frame(width: AppLayout.colorSliderGlowSize, height: AppLayout.colorSliderGlowSize)
                        .offset(x: spot - AppLayout.colorSliderGlowSize / 2)
                }

                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.2)))
                    .frame(width: AppLayout.colorSliderThumbSize, height: AppLayout.colorSliderThumbSize)
                    .offset(x: spot - radius)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(.rect)
            // A high-priority gesture, because these live in a scroll view and a
            // drag that starts on a slider belongs to the slider — otherwise the
            // panel scrolls out from under the finger and the value never moves.
            .highPriorityGesture(drag(travel: travel, radius: radius))
        }
        .frame(height: AppLayout.colorSliderHitHeight)
        // A cursor that says the control is dragged sideways. macOS has no
        // pointer at all over a view that does not ask for one, which leaves the
        // track looking like something to read rather than something to move.
        .pointerStyle(.columnResize)
        // Focusable for the arrow keys, and drawn without a ring: eleven sliders
        // in a column, each drawing one the moment it is clicked, is a column of
        // boxes. Nothing else is lost — the keys still work, and the value still
        // moves — but a keyboard user has no indication of which slider they are
        // on beyond the value changing as they press.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            nudge(by: -step)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            nudge(by: step)
            return .handled
        }
        // What the control *is*, for anyone not using a pointer: a slider is
        // adjustable, in steps, and reports where it is. Handing those over as a
        // representation rather than as modifiers is what makes the four shapes
        // above one element of the right kind rather than four of the wrong one.
        //
        // Represented in the numbers the panel draws — whole percents — rather
        // than in the recipe's normalized ones, so what is spoken is the same
        // figure that is on screen beside it.
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { value * 100 }, set: { value = $0 / 100 }),
                in: (range.lowerBound * 100)...(range.upperBound * 100),
                step: step * 100
            ) {
                label
            }
            .accessibilityIdentifier(identifier)
        }
    }

    // MARK: - Dragging

    /// A drag, converted to a value across the same travel the thumb is drawn
    /// across — handed over rather than worked out again here, so a hit and a
    /// pixel cannot disagree about where the ends are.
    private func drag(travel: CGFloat, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard travel > 0 else { return }
                // The pointer's own position, not a step to add: a drag reports
                // its whole translation on every callback, so adding one would
                // walk the thumb away from the finger.
                value = Self.value(at: Double((gesture.location.x - radius) / travel), in: range)
            }
            .onEnded { _ in
                onCommit()
            }
    }

    /// A move from the keyboard or an assistive technology.
    private func nudge(by delta: Double) {
        value = (value + delta).clamped(to: range)
    }

    // MARK: - Where a value sits

    /// Where a value sits along the track, in `0...1`.
    static func position(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clamped(to: 0...1)
    }

    /// The value at a point along the track, in `0...1`.
    ///
    /// Clamped rather than wrapped: a drag that runs off the end of a slider is
    /// asking for its end, and asking for it repeatedly should not walk the
    /// value around the range.
    static func value(at position: Double, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + position.clamped(to: 0...1) * (range.upperBound - range.lowerBound)
    }
}
