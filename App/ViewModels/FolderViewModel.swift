//
//  FolderViewModel.swift
//  Photon
//

import Foundation
import Observation

/// Window-scoped view model: the folder *this* window is working in.
///
/// Owned by ``RootView`` with `@State`, so each window of the scene gets its own
/// instance. Two windows can hold two different folders, and picking one in a
/// window leaves every other window alone.
@Observable
@MainActor
final class FolderViewModel {
    /// Progress through the folder picker.
    ///
    /// Separate from ``phase`` because picking is orthogonal to routing: it can
    /// start from either screen.
    enum FolderPick: Equatable {
        case idle
        /// The system picker is on screen.
        case presenting
        /// A folder was picked and is being opened.
        case opening
    }

    /// What this window is showing.
    private(set) var phase: AppPhase

    /// Progress through the folder picker, when one is in flight.
    private(set) var folderPick: FolderPick = .idle

    /// The failure to surface in an alert, or `nil` when there is nothing to
    /// report.
    private(set) var failure: FolderAccessError?

    private let app: AppViewModel

    init(app: AppViewModel) {
        self.app = app
        // A launch with nothing to resolve settles on the welcome screen
        // straight away, so a first run never shows the placeholder.
        self.phase = app.isLaunchPending ? .starting : .welcome(notice: nil)
    }

    // MARK: - Launch

    /// Settles the window onto whichever screen it should open at.
    ///
    /// Safe to call more than once: only a window still ``AppPhase/starting``
    /// does anything. A window opened after the first one finds the launch
    /// result already claimed and stays on the welcome screen.
    func start() async {
        guard phase == .starting, let outcome = await app.claimLaunchOutcome() else { return }

        phase =
            switch outcome {
            case .noRememberedFolder: .welcome(notice: nil)
            case .reopened(let folder): .editing(folder)
            case .couldNotReopen: .welcome(notice: .rememberedFolderUnavailable)
            }
    }

    // MARK: - Choosing a folder

    /// Two-way flag for the view's `fileImporter(isPresented:)`, derived from
    /// ``folderPick`` so the two cannot disagree about whether a pick is in
    /// flight.
    var isChoosingFolder: Bool {
        get { folderPick == .presenting }
        set {
            if newValue {
                folderPick = .presenting
            } else if folderPick == .presenting {
                // Only clear a pick that is still pending: dismissal must not
                // clobber a folder that is already being opened.
                folderPick = .idle
            }
        }
    }

    /// Shows the system folder picker.
    func chooseFolder() {
        folderPick = .presenting
    }

    /// Opens the folder the system picker returned.
    ///
    /// A cancelled pick arrives as a failure and simply returns to
    /// ``FolderPick/idle``. A folder that fails to open leaves ``phase``
    /// untouched, so a failed switch from the editor keeps the current folder.
    func handleSelection(_ result: Result<[URL], any Error>) async {
        defer { folderPick = .idle }

        guard case .success(let urls) = result, let url = urls.first else { return }
        folderPick = .opening

        do {
            phase = .editing(try await app.openFolder(at: url))
        } catch {
            // `openFolder` is typed `throws(FolderAccessError)`, so this is the
            // only error it can be.
            failure = error
        }
    }

    /// Discards the remembered folder and clears the notice offering to.
    func forgetRememberedFolder() {
        app.forgetRememberedFolder()
        if case .welcome = phase {
            phase = .welcome(notice: nil)
        }
    }

    // MARK: - Failures

    /// Two-way flag for the view's `alert(isPresented:)`, derived from
    /// ``failure`` so the alert and the state cannot disagree.
    var isShowingFailure: Bool {
        get { failure != nil }
        set {
            if !newValue { failure = nil }
        }
    }
}
