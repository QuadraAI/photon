//
//  FileOpener.swift
//  Photon
//

#if os(macOS)
import AppKit
import Foundation

/// Opens an exported file in the application that owns it.
///
/// SwiftUI's `openURL` is the usual way, but on macOS a sandboxed app has to ask
/// LaunchServices to open a file outside its container, and `NSWorkspace` is
/// that request. Kept macOS-only and single-purpose, like the window-maximiser
/// wrapper, so no AppKit reaches view logic.
@MainActor
enum FileOpener {
    /// - Returns: Whether LaunchServices accepted the request to open the file.
    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
#endif
