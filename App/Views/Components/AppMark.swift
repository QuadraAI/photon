//
//  AppMark.swift
//  Photon
//

import SwiftUI

/// Photon's aperture mark.
///
/// Shared rather than duplicated: the launch placeholder and the welcome screen
/// have to line up exactly, so a fast resolve reads as the same screen
/// continuing instead of a flicker between two layouts.
struct AppMark: View {
    var body: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: 56))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}
