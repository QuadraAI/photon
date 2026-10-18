//
//  PhotoExportError+Presentation.swift
//  Photon
//

import SwiftUI

extension PhotoExportError {
    /// What the export sheet tells the user to do about it.
    ///
    /// A `LocalizedStringKey`, not a `String`, so it re-resolves when the app's
    /// language changes.
    var message: LocalizedStringKey {
        switch self {
        case .unreadable: "error.export.unreadable.message"
        case .couldNotEncode: "error.export.couldNotEncode.message"
        case .couldNotWrite: "error.export.couldNotWrite.message"
        case .cancelled: "error.export.cancelled.message"
        }
    }
}
