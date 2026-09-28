//
//  View+AppPresentation.swift
//  Photon
//

import SwiftUI

extension View {
    /// Applies the user's language and appearance to everything below.
    ///
    /// ``RootView`` does this once for the running app. Anywhere a screen is
    /// built outside `RootView` — previews, mainly — has to apply it too, or it
    /// silently renders in the device language instead of the chosen one.
    func appPresentation(_ preferences: AppPreferences) -> some View {
        self
            // Re-resolving `Text` against this locale is what makes the language
            // menu take effect without a relaunch.
            .environment(\.locale, preferences.language.locale)
            // `nil` hands appearance back to the system.
            .preferredColorScheme(preferences.theme.colorScheme)
    }
}
