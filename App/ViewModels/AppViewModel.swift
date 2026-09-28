//
//  AppViewModel.swift
//  Photon
//

import Foundation
import Observation
import os

/// App-scoped view model: the settings and services that outlive any one window,
/// plus the once-per-launch attempt to reopen the remembered folder.
///
/// Which folder a window is working in deliberately does **not** live here. That
/// is ``FolderViewModel``, owned per window — `@State` on an `App` is shared by
/// every window of the scene, so keeping routing state here would make File ▸
/// New Window show the same folder, and make picking a folder in one window drag
/// every other window along with it.
@Observable
@MainActor
final class AppViewModel {
    /// The user's settings, mirrored from the store so views react to them.
    private(set) var preferences: AppPreferences

    private let logger = Logger(subsystem: "com.quadra.Photon", category: "AppViewModel")
    private let preferencesStore: PreferencesStoring
    private let bookmarkStore: BookmarkStoring
    private let folderAccess: FolderAccessing
    private var hasClaimedLaunchOutcome = false

    init(
        preferencesStore: PreferencesStoring,
        bookmarkStore: BookmarkStoring,
        folderAccess: FolderAccessing
    ) {
        self.preferencesStore = preferencesStore
        self.bookmarkStore = bookmarkStore
        self.folderAccess = folderAccess
        self.preferences = preferencesStore.load()
    }

    // MARK: - Settings

    /// Replaces the interface language and persists the choice.
    func setLanguage(_ language: AppLanguage) {
        update { $0.language = language }
    }

    /// Replaces the appearance and persists the choice.
    func setTheme(_ theme: AppTheme) {
        update { $0.theme = theme }
    }

    // MARK: - Folders

    /// Whether this launch still has a remembered folder to resolve.
    ///
    /// False on a first run, and false for every window after the first, so
    /// neither has to show the launch placeholder before settling.
    var isLaunchPending: Bool {
        !hasClaimedLaunchOutcome && bookmarkStore.loadBookmark() != nil
    }

    /// Opens `url` and records it as the folder to reopen next launch.
    ///
    /// - Throws: ``FolderAccessError`` when the folder cannot be opened. A
    ///   bookmark the system would not mint is not an error — the folder works
    ///   either way, it just will not be reopened next time.
    func openFolder(at url: URL) async throws(FolderAccessError) -> AuthorizedFolder {
        let folder = try await folderAccess.authorize(url)
        bookmarkStore.saveBookmark(folder.bookmark)
        return folder
    }

    /// Hands the launch result to the first window that asks for it.
    ///
    /// - Returns: The outcome for the first caller, or `nil` for windows opened
    ///   afterwards, which start fresh.
    func claimLaunchOutcome() async -> LaunchOutcome? {
        guard !hasClaimedLaunchOutcome else { return nil }
        hasClaimedLaunchOutcome = true

        guard let bookmark = bookmarkStore.loadBookmark() else {
            return .noRememberedFolder
        }

        do {
            let folder = try await folderAccess.restore(bookmark)
            // A stale bookmark is refreshed by `restore`, so always write back.
            bookmarkStore.saveBookmark(folder.bookmark)
            return .reopened(folder)
        } catch {
            logger.error("Could not reopen the remembered folder: \(String(describing: error))")
            return .couldNotReopen
        }
    }

    /// Discards the remembered folder so Photon stops trying to reopen it.
    func forgetRememberedFolder() {
        bookmarkStore.saveBookmark(nil)
    }

    // MARK: - Internals

    private func update(_ mutate: (inout AppPreferences) -> Void) {
        var updated = preferences
        mutate(&updated)
        guard updated != preferences else { return }

        preferences = updated
        preferencesStore.save(updated)
    }
}
