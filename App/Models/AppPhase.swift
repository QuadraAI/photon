//
//  AppPhase.swift
//  Photon
//

import Foundation

/// What the app is showing.
///
/// Modelled as one enum rather than a set of flags so the two screens can never
/// both claim to be on top, and so "we have not decided yet" is a state rather
/// than an absence.
nonisolated enum AppPhase: Equatable, Sendable {
    /// Resolving the remembered folder. Neither screen should be on show yet —
    /// rendering the welcome screen first and snatching it away once the folder
    /// opens would flash the wrong thing at launch.
    case starting

    /// No folder is open. `notice` explains why a remembered one was not
    /// reopened, when there was one to reopen.
    case welcome(notice: WelcomeNotice?)

    /// A folder is open and ready to work in.
    case editing(AuthorizedFolder)
}
