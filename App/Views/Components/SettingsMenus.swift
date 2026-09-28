//
//  SettingsMenus.swift
//  Photon
//

import SwiftUI

/// The language and appearance menus, pinned to the top-trailing corner of
/// whichever screen is on show.
struct SettingsMenus: View {
    var body: some View {
        // The trailing `Spacer` lives in the *outer* horizontal stack on
        // purpose: a spacer inside the vertical variant would expand downwards
        // and squash the rest of the screen.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SettingsMenuButtons()
        }
        .padding(16)
    }
}
