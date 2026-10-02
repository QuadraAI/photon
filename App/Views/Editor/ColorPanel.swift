//
//  ColorPanel.swift
//  Photon
//

import SwiftUI

/// The colour tool's controls.
///
/// Two halves, in the order the pipeline applies them. First the three sliders
/// that move every colour at once — saturation, vibrance, and the one that takes
/// the photo's own cast out. Then the eight bands, which move one colour each, in
/// whichever of the three modes the picker is on.
///
/// A band is a window on hue rather than a set of pixels: raising yellow's
/// saturation raises everything the eye would call yellow, and passes over to
/// orange and green as the hue moves between them. That is why one row per band
/// is enough to correct a photograph, and why the rows between them are not
/// needed.
///
/// The panel edits a *draft*. A drag is one change and one history step, closed
/// when the pointer is let go — or, for a change made from the keyboard or
/// VoiceOver, which has no pointer to let go of, when the panel or the photo
/// changes.
struct ColorPanel: View {
    @Environment(EditorViewModel.self) private var editor

    /// Which of the three things the band sliders change.
    ///
    /// Local to the panel, and deliberately not part of the recipe: a mode is how
    /// the sliders are being *read*, not something done to the photo. Two windows
    /// on the same photograph should be able to look at different ones.
    @State private var channel: HSLChannel = .saturation

    /// How far one arrow key, or one VoiceOver swipe, moves a slider.
    private static let step = 0.01

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // No heading over the first three: the panel's own says
                    // "Color", and saying it twice would be one title too many.
                    globals
                        .padding(.top, 6)

                    Divider().padding(.top, 12)

                    section("tool.color.hsl.title")
                    picker
                    bands
                }
                .padding(.bottom, 12)
            }

            Divider()
            actions
        }
    }

    // MARK: - The three that move every colour

    private var globals: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(
                "tool.color.saturation",
                value: binding({ editor.colorAdjustments.saturation }, editor.setSaturation),
                identifier: "tool.color.saturation"
            )

            row(
                "tool.color.vibrance",
                value: binding({ editor.colorAdjustments.vibrance }, editor.setVibrance),
                identifier: "tool.color.vibrance"
            )

            // Only ever takes a cast out, so it rests at nothing rather than in
            // the middle of a range that would have no use for the other half.
            row(
                "tool.color.colorCast",
                value: binding({ editor.colorAdjustments.colorCast }, editor.setColorCast),
                range: ColorAdjustments.colorCastRange,
                neutral: ColorAdjustments.colorCastRange.lowerBound,
                identifier: "tool.color.colorCast"
            )
        }
    }

    // MARK: - The eight that move one colour each

    private var picker: some View {
        Menu {
            ForEach(HSLChannel.allCases, id: \.self) { option in
                Button {
                    channel = option
                } label: {
                    Label {
                        Text(option.name)
                    } icon: {
                        option.swatch
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                channel.swatch
                    .frame(width: 16, height: 16)

                Text(channel.name)
                    .font(.callout)

                Spacer(minLength: 0)
                // No chevron of our own: a `Menu` draws the one that says it
                // opens, and two of them side by side say it twice.
            }
            .contentShape(.rect)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityLabel("tool.color.channel")
        .accessibilityValue(channel.name)
        .accessibilityIdentifier("tool.color.channel")
    }

    private var bands: some View {
        // Read once, outside the loop, so the loop's own body is not a property
        // read per row.
        let mode = channel

        return ForEach(ColorBand.allCases, id: \.self) { band in
            row(
                band.name,
                value: binding(
                    { editor.colorAdjustments[mode, in: band] },
                    { editor.setBand(mode, band, to: $0) }
                ),
                tint: band.color,
                ramp: mode.ramp(for: band),
                identifier: "tool.color.band.\(band.rawValue).\(mode.rawValue)",
                spoken: Text("tool.color.band.slider \(Text(band.name)) \(Text(mode.name))")
            )
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("tool.color.reset") {
                editor.resetColor()
            }
            .disabled(editor.colorAdjustments.isIdentity)
            .accessibilityHint("tool.color.reset.hint")
            .accessibilityIdentifier("tool.color.reset")

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK: - One row

    /// A slider with its name and value on the line above it.
    ///
    /// The value is read back from the recipe rather than kept beside it, so the
    /// number, the thumb and the canvas cannot end up telling three stories.
    ///
    /// - Parameters:
    ///   - range: What the slider runs over. The bipolar range by default, which
    ///     is every row but the cast.
    ///   - neutral: Where it rests, and what its reset returns it to.
    ///   - tint: What fills the track toward the thumb, and colours the thumb.
    ///     The app's accent by default, which is what the three global sliders
    ///     want; the bands pass their own colour.
    ///   - ramp: What the whole track runs through. Left out, the tint from
    ///     nothing to itself, which is what a slider that is not about a colour
    ///     wants.
    ///   - spoken: What VoiceOver calls it, when the drawn label is not enough —
    ///     a band's row is named for its colour, and its slider has to say which
    ///     of the three things that colour is being asked to do.
    private func row(
        _ label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double> = ColorAdjustments.range,
        neutral: Double = 0,
        tint: Color = .accentColor,
        ramp: [Color]? = nil,
        identifier: String,
        spoken: Text? = nil
    ) -> some View {
        let number = value.wrappedValue
        let name = spoken ?? Text(label)
        let colours = ramp ?? [tint.opacity(0.3), tint]

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.callout)

                Spacer(minLength: 0)

                // Unsigned, as the sliders it is copied from are: the thumb says
                // which side of nothing the value is on, and the value the slider
                // speaks says it again for anyone who cannot see the thumb.
                Text(number * 100, format: .number.precision(.fractionLength(0)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                reset(value, neutral: neutral, label: name, identifier: identifier)
            }

            GradientSlider(
                value: value,
                range: range,
                neutral: neutral,
                tint: tint,
                ramp: colours,
                label: name,
                step: Self.step,
                identifier: identifier,
                onCommit: { editor.endColorChange() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// Back to nothing for one slider, without disturbing the other ten.
    ///
    /// Present only when there is something to take back: an always-there reset
    /// on eleven rows is eleven controls that mostly do nothing, and a control
    /// that does nothing is one a keyboard has to walk past.
    private func reset(
        _ value: Binding<Double>,
        neutral: Double,
        label: Text,
        identifier: String
    ) -> some View {
        let isNeutral = value.wrappedValue == neutral

        return Button {
            value.wrappedValue = neutral
            editor.endColorChange()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption2)
                .frame(width: 16, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isNeutral ? 0 : 1)
        .disabled(isNeutral)
        .accessibilityHidden(isNeutral)
        .accessibilityLabel(Text("tool.color.reset.one \(label)"))
        .accessibilityIdentifier("\(identifier).reset")
    }

    // MARK: - Writing

    /// A slider's value, read from the photo and written back as a change.
    ///
    /// Opening the change is what the first write of a drag does, rather than the
    /// drag itself having to say so: a drag, a nudge from the keyboard and a
    /// swipe from VoiceOver all come through here, and all three are the same
    /// thing — a slider being moved.
    private func binding(
        _ read: @escaping () -> Double,
        _ write: @escaping (Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: read,
            set: { value in
                editor.beginColorChange()
                write(value)
            }
        )
    }

    // MARK: - Presentation

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
