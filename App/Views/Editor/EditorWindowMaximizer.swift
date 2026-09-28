//
//  EditorWindowMaximizer.swift
//  Photon
//

#if os(macOS)
import AppKit
import SwiftUI

/// Expands the window to fill the screen's usable area when the editor opens.
///
/// This is the green button's *zoom*, not `toggleFullScreen`: `visibleFrame`
/// keeps the menu bar and Dock. It is macOS-only, and the only AppKit in the
/// feature — SwiftUI has no way to resize a window after it has been created,
/// because `defaultSize` and `defaultWindowPlacement` are both evaluated at
/// creation time.
struct EditorWindowMaximizer: NSViewRepresentable {
    /// Called once the frame has been set, so the window does not fight a user
    /// who resizes it afterwards.
    let onMaximized: () -> Void

    func makeNSView(context: Context) -> NSView {
        MaximizingView(onMaximized: onMaximized)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MaximizingView: NSView {
    private let onMaximized: () -> Void
    private var hasMaximized = false

    init(onMaximized: @escaping () -> Void) {
        self.onMaximized = onMaximized
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// `window` is nil during `makeNSView`, so the frame can only be set once the
    /// view has actually been attached.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard !hasMaximized, let window, let screen = window.screen else { return }
        hasMaximized = true

        // A window with a hidden title bar is draggable by its background, which
        // would fight any drag the content wants for itself — the resizable
        // dividers today, panning the canvas later. The title-bar strip stays a
        // drag handle, so the window is still movable.
        window.isMovableByWindowBackground = false

        window.setFrame(screen.visibleFrame, display: true, animate: true)

        // Deferred so the callback cannot mutate observable state in the middle
        // of a SwiftUI view update.
        Task { @MainActor in onMaximized() }
    }
}
#endif
