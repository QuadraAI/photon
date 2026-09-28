//
//  FolderAccessError+Presentation.swift
//  Photon
//

import SwiftUI

extension FolderAccessError {
    /// Alert body telling the user what to do about it.
    ///
    /// The alert's *title* is a single generic key. Deriving it from the error
    /// would need a non-optional `LocalizedStringKey`, which forces a `?? ""`
    /// fallback — and an empty literal gets extracted into the String Catalog as
    /// a stray `""` entry.
    var message: LocalizedStringKey {
        switch self {
        case .notADirectory: "error.notADirectory.message"
        case .accessDenied: "error.accessDenied.message"
        case .bookmarkResolutionFailed: "error.bookmarkResolutionFailed.message"
        }
    }
}
