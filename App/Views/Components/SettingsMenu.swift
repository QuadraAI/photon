//
//  SettingsMenu.swift
//  Photon
//

import SwiftUI

/// The language and appearance settings, folded into one overflow menu.
///
/// The editor's toolbar already carries a sidebar toggle, undo and redo. Two
/// full menus beside them leave no room for the photo's name at the centre,
/// where the welcome screen has space to spend and keeps them side by side.
struct SettingsMenu: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        Menu {
            Picker("settings.language", selection: language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.menuTitle).tag(language)
                }
            }

            Picker("settings.appearance", selection: theme) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.menuTitle, systemImage: theme.symbolName).tag(theme)
                }
            }
        } label: {
            Label("settings.title", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                // Padding inside the label, not outside the menu: the label is
                // the control's content, so growing it grows the button and its
                // hit area together. Padding on the menu only grew the space
                // around it, which is what left a large shell around a small
                // button that still had the small button's target.
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(.rect)
        }
        .accessibilityLabel("settings.title")
        .accessibilityIdentifier("editor.toolbar.settings")
    }

    private var language: Binding<AppLanguage> {
        Binding(
            get: { app.preferences.language },
            set: { app.setLanguage($0) }
        )
    }

    private var theme: Binding<AppTheme> {
        Binding(
            get: { app.preferences.theme },
            set: { app.setTheme($0) }
        )
    }
}
