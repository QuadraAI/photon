//
//  EditorView.swift
//  Photon
//

import SwiftUI

/// The editing surface: a media sidebar, the selected photo, and the tool rail.
///
/// The sidebar is a real split-view column rather than a pane in an `HStack`.
/// That is what lets the window toolbar place its items against the sidebar's
/// divider: AppKit tracks a split view's divider, so a toolbar item can be told
/// to follow one, and the system emits that tracking separator for us. A
/// hand-rolled pane has no divider, so its items had nothing to follow and sat
/// over the sidebar instead of beside it.
struct EditorView: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let folder: AuthorizedFolder

    /// How far the media sidebar pushes the detail column right, in points — and
    /// zero while the sidebar is hidden.
    ///
    /// Measured rather than assumed, because the column is the user's to drag and
    /// this is also the outset macOS gives the toolbar's items when it tracks the
    /// sidebar's divider. The title capsule pays half of it back.
    @State private var sidebarOffset: CGFloat = 0

    /// The split view's own width, and where the canvas sits inside it.
    ///
    /// Together they are the canvas's place in the window, which is what its
    /// placeholders centre on. Read from the layout rather than worked out from
    /// which panes are open, so they hold *while* a pane animates: a placeholder
    /// offset by an arithmetic guess jumps when the guess changes, and then
    /// drifts back as the pane catches up.
    @State private var windowWidth: CGFloat = 0
    @State private var canvasMidX: CGFloat = 0

    /// Space the detail column's leading edge is measured in. Named rather than
    /// `.global` so the number is the sidebar's width alone, with no window
    /// position folded into it.
    ///
    /// `nonisolated` because `onGeometryChange` reads it from a `@Sendable`
    /// closure, which the target's main-actor-by-default isolation would
    /// otherwise put out of reach.
    private nonisolated static let splitViewSpace = "photon.editor.splitView"

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            MediaSidebar()
                .navigationSplitViewColumnWidth(
                    min: AppLayout.mediaSidebarWidthRange.lowerBound,
                    ideal: AppLayout.mediaSidebarWidth,
                    max: AppLayout.mediaSidebarWidthRange.upperBound
                )
        } detail: {
            workspace
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.splitViewSpace)).minX
                } action: { offset in
                    sidebarOffset = offset
                }
        }
        .coordinateSpace(.named(Self.splitViewSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
        }
        .background(.background)
        .toolbar {
            EditorToolbar(
                folderName: folder.url.lastPathComponent,
                sidebarOffset: sidebarOffset
            )
        }
        .plainWindowToolbar()
        .toolbar(removing: .title)
        .task(id: folder.url) {
            await editor.load(folder)
        }
    }

    /// The view model owns sidebar visibility, so the column reports to it rather
    /// than the two keeping separate state that can drift apart.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { editor.isSidebarVisible ? .all : .detailOnly },
            set: { editor.isSidebarVisible = $0 != .detailOnly }
        )
    }

    private var workspace: some View {
        // Deliberately no `GlassEffectContainer`: it hoists its children's glass
        // into a shared layer, which put each pane's surface *above* its own
        // content and left the sidebar's rows a blurred smear behind it. The
        // panes abut without one, and none of them needs the other's glass.
        HStack(spacing: 0) {
            PhotoCanvas(windowCentreOffset: windowWidth / 2 - canvasMidX)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.splitViewSpace)).midX
                } action: { midX in
                    canvasMidX = midX
                }

            if let tool = editor.openTool {
                HStack(spacing: 0) {
                    ResizableDivider(
                        width: panelWidth,
                        range: AppLayout.toolPanelWidthRange,
                        dragSign: -1,
                        label: "editor.divider.panel",
                        identifier: "editor.divider.panel"
                    )

                    ToolPanel(tool: tool)
                }
                .surfaced()
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            ToolRail()
                .surfaced()
        }
        .animation(motion, value: editor.openTool)
        .overlay(alignment: .topLeading) { windowMaximizer }
    }

    /// Clamped in the view model, so a drag that runs off the end of the range
    /// is absorbed rather than banked.
    private var panelWidth: Binding<CGFloat> {
        Binding(
            get: { editor.panelWidth },
            set: { editor.setPanelWidth($0) }
        )
    }

    /// Nil under Reduce Motion, which is how the width changes become instant
    /// rather than animated.
    private var motion: Animation? {
        reduceMotion ? nil : .default
    }

    /// Inserted only until it has run, which is what keeps the window from being
    /// resized again every time the user opens a different folder.
    @ViewBuilder private var windowMaximizer: some View {
        #if os(macOS)
        if !editor.hasMaximizedWindow {
            EditorWindowMaximizer { editor.markWindowMaximized() }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        #endif
    }
}

private extension View {
    /// Hands the toolbar's own background back, so what is behind the bar shows
    /// through it rather than being covered by a material of its own.
    ///
    /// macOS-only: a window toolbar is a macOS idea, and iPadOS has no
    /// equivalent background to suppress.
    @ViewBuilder func plainWindowToolbar() -> some View {
        #if os(macOS)
        toolbarBackground(.hidden, for: .windowToolbar)
        #else
        self
        #endif
    }

    /// A pane's surface: glass behind the pane, run up to the window's top edge
    /// so it passes under the toolbar.
    ///
    /// Only the surface goes up; the pane's content stays where the safe area
    /// puts it, below the bar. The media sidebar doesn't need this — as a
    /// split-view column the system draws its material, and runs it to the top
    /// itself.
    func surfaced() -> some View {
        background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea(edges: .top)
        }
    }
}
