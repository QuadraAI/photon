//
//  AppearanceMenu.swift
//  Photon
//

import SwiftUI

/// Top-right menu for overriding the system appearance.
struct AppearanceMenu: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        Menu {
            Picker("settings.appearance", selection: theme) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.menuTitle, systemImage: theme.symbolName).tag(theme)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(app.preferences.theme.menuTitle, systemImage: app.preferences.theme.symbolName)
        }
        .accessibilityLabel("settings.appearance")
        .accessibilityValue(app.preferences.theme.menuTitle)
    }

    private var theme: Binding<AppTheme> {
        Binding(
            get: { app.preferences.theme },
            set: { app.setTheme($0) }
        )
    }
}
