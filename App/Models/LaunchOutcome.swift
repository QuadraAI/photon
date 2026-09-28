//
//  LaunchOutcome.swift
//  Photon
//

import Foundation

/// What the once-per-launch attempt to reopen a remembered folder produced.
///
/// App-scoped rather than window-scoped on purpose: the attempt happens once per
/// launch, and only the first window gets to see it. A window opened later via
/// File ▸ New Window starts on the welcome screen instead of duplicating the
/// folder this launch already reopened.
nonisolated enum LaunchOutcome: Equatable, Sendable {
    /// Nothing was remembered, so there is nothing to reopen.
    case noRememberedFolder

    /// The remembered folder is open.
    case reopened(AuthorizedFolder)

    /// A folder was remembered but would not open.
    case couldNotReopen
}
