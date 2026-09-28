//
//  LanguageMenu.swift
//  Photon
//

import SwiftUI

/// Top-right menu for switching the interface language.
///
/// The label always shows the active choice, so the control still reads
/// correctly when the user cannot tell the languages apart.
struct LanguageMenu: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        Menu {
            Picker("settings.language", selection: language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.menuTitle).tag(language)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(app.preferences.language.menuTitle, systemImage: "globe")
        }
        .accessibilityLabel("settings.language")
        .accessibilityValue(app.preferences.language.menuTitle)
    }

    /// Writes straight through to the view model so the choice is persisted the
    /// moment it changes.
    private var language: Binding<AppLanguage> {
        Binding(
            get: { app.preferences.language },
            set: { app.setLanguage($0) }
        )
    }
}
