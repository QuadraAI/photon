//
//  AppLanguage+Presentation.swift
//  Photon
//

import SwiftUI

extension AppLanguage {
    /// Name shown in the language menu.
    ///
    /// A ``LocalizedStringKey`` rather than a `String` so the menu re-renders in
    /// the newly picked language the moment it changes.
    ///
    /// There is no icon per language: a globe beside "English" and another
    /// beside "French" would carry no information.
    var menuTitle: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .french: "language.french"
        }
    }
}
