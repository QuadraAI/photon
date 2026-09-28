//
//  WelcomeNotice.swift
//  Photon
//

import Foundation

/// Something the welcome screen should explain to the user.
///
/// Notices are inline and non-blocking. An alert would steal focus at launch,
/// before the user has any idea where they are.
nonisolated enum WelcomeNotice: Equatable, Sendable {
    /// The folder Photon remembered could not be reopened.
    ///
    /// The bookmark is kept rather than discarded: a folder on an unplugged
    /// drive looks exactly like a folder that was deleted, and forgetting it
    /// would lose the memory for the case where the volume comes back. The
    /// welcome screen offers an explicit way to clear it instead.
    case rememberedFolderUnavailable
}
