//
//  SettingsMenuButtons.swift
//  Photon
//

import SwiftUI

/// The language and appearance menus as a group, with no surrounding layout.
///
/// Split out of ``SettingsMenus`` so the editor's toolbar can host the same two
/// menus inside its own leading/trailing arrangement, rather than inheriting the
/// welcome screen's full-width bar.
struct SettingsMenuButtons: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // `AnyLayout` — rather than an `if` — keeps this a single view hierarchy
        // while still stacking the menus once Dynamic Type reaches the
        // accessibility sizes and two side-by-side menus would no longer fit.
        menus {
            LanguageMenu()
            AppearanceMenu()
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
    }

    private var menus: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }
}
