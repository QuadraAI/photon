//
//  ColorBand+Presentation.swift
//  Photon
//

import SwiftUI

extension ColorBand {
    /// What the band's row reads, and what its slider is announced as.
    var name: LocalizedStringKey {
        switch self {
        case .red: "tool.color.band.red"
        case .orange: "tool.color.band.orange"
        case .yellow: "tool.color.band.yellow"
        case .green: "tool.color.band.green"
        case .cyan: "tool.color.band.cyan"
        case .blue: "tool.color.band.blue"
        case .purple: "tool.color.band.purple"
        case .magenta: "tool.color.band.magenta"
        }
    }

    /// The colour a band's row is drawn in: its slider's fill, its glow and the
    /// swatch beside its name.
    ///
    /// Never the only thing saying which band a row is — every row is labelled
    /// with its name, and its value is a number — so this is decoration that
    /// happens to be useful. Magenta is pink because SwiftUI has no magenta, and
    /// pink is the nearest thing that still reads as one.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .cyan: .cyan
        case .blue: .blue
        case .purple: .purple
        case .magenta: .pink
        }
    }
}

extension HSLChannel {
    /// What the mode picker calls it.
    var name: LocalizedStringKey {
        switch self {
        case .hue: "tool.color.channel.hue"
        case .saturation: "tool.color.channel.saturation"
        case .luminance: "tool.color.channel.luminance"
        }
    }

    /// The colours a band's track runs through in this mode, left to right.
    ///
    /// The track is a picture of what the slider does, so it changes with the
    /// mode: a hue slider walks a colour toward its neighbours round the circle,
    /// which is why they are the ramp's ends; saturation runs from the grey the
    /// colour loses to the colour itself; luminance runs from black through the
    /// colour to white.
    func ramp(for band: ColorBand) -> [Color] {
        switch self {
        case .hue: [band.previous.color, band.color, band.next.color]
        case .saturation: [.gray, band.color]
        case .luminance: [.black, band.color, .white]
        }
    }

    /// The disc that stands for the mode in the picker.
    ///
    /// The three are the three pictures of what the sliders do: the whole hue
    /// circle, one colour going from grey to itself, and black to white.
    @ViewBuilder var swatch: some View {
        switch self {
        case .hue:
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                        center: .center
                    )
                )
        case .saturation:
            Circle()
                .fill(LinearGradient(colors: [.gray, .red], startPoint: .leading, endPoint: .trailing))
        case .luminance:
            Circle()
                .fill(LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing))
        }
    }
}
