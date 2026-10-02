//
//  AppLayout.swift
//  Photon
//

import CoreGraphics

/// Layout constants the screens and their previews share.
///
/// Centralised rather than repeated so a preview cannot quietly drift from the
/// window the app actually opens — which is exactly how the previews once ended
/// up rendering at the wrong proportions and making a centred layout look wrong.
enum AppLayout {
    /// The size `Photon`'s window opens at.
    ///
    /// Only applies to a window with no saved frame; macOS remembers where the
    /// user last put things.
    static let windowSize = CGSize(width: 640, height: 520)

    /// Widest the content column grows, so text keeps a readable measure on a
    /// wide window instead of stretching edge to edge.
    static let contentColumnWidth: CGFloat = 520

    /// How wide the media sidebar opens, and how far it can be dragged.
    ///
    /// Handed to the split view rather than applied as a frame: the column owns
    /// its own width now, and clamps to this range on its own.
    static let mediaSidebarWidth: CGFloat = 220
    static let mediaSidebarWidthRange: ClosedRange<CGFloat> = 160...420

    /// How wide the tool panel opens, and how far it can be dragged.
    static let toolPanelWidth: CGFloat = 240
    static let toolPanelWidthRange: ClosedRange<CGFloat> = 200...420

    /// Width of the tool rail, and the grab area of a pane divider.
    static let toolRailWidth: CGFloat = 52
    static let dividerHitWidth: CGFloat = 10

    /// Width reserved for a row's kind glyph in the media sidebar.
    static let sidebarGlyphWidth: CGFloat = 18

    /// The window toolbar's sidebar toggle: 40pt wide, its trailing edge 4pt
    /// inside the sidebar's divider.
    ///
    /// The sidebar's photo count is drawn in a box of the same width, pushed to
    /// the same trailing edge, so the two share an axis instead of the count
    /// sitting hard against the sidebar's edge.
    static let sidebarToggleWidth: CGFloat = 40
    static let sidebarCountTrailingInset: CGFloat = 2

    /// Size of the glass capsule around the editor's title, matching the camera
    /// housing on a 14" or 16" MacBook Pro — the width and height of that notch,
    /// so the capsule reads as the same piece of hardware rather than a label
    /// that happens to be centred.
    static let toolbarTitleWidth: CGFloat = 200
    static let toolbarTitleHeight: CGFloat = 32

    /// Strip the preview canvas draws its own window chrome in.
    ///
    /// The app's toolbar lives in the window's real toolbar; the canvas has no
    /// equivalent, so a preview reserves the space to stand in for it.
    static let previewToolbarInset: CGFloat = 52

    /// Longest edge of a decoded preview, in pixels.
    ///
    /// Comfortably larger than any canvas on a 2× display, and small enough that
    /// stepping through a folder stays responsive.
    static let previewMaxPixelSize = 2048

    /// How big a crop handle is drawn, and how much of the canvas catches a drag
    /// on it.
    ///
    /// The two differ because 14 points is a fair target for a mouse and an
    /// impossible one for a finger: the smaller square is what the user aims at,
    /// the larger one is what actually responds.
    static let cropHandleSize: CGFloat = 14
    #if os(iOS)
    static let cropHitTarget: CGFloat = 44
    #else
    static let cropHitTarget: CGFloat = 24
    #endif

    /// Width of a rule-of-thirds line inside the crop.
    static let cropGridLineWidth: CGFloat = 0.5

    /// How a colour slider is drawn: a thin track under a round thumb.
    ///
    /// The track is thin because there are eleven of them in one panel and none
    /// is the point on its own, and the thumb is small for the same reason. What
    /// catches the drag is neither: see ``colorSliderHitHeight``.
    static let colorSliderTrackHeight: CGFloat = 4
    static let colorSliderThumbSize: CGFloat = 14

    /// The halo behind a colour slider's thumb.
    ///
    /// Wider than the thumb and much fainter, so it reads as the colour spilling
    /// out of the thumb rather than as a second, larger control on the track.
    static let colorSliderGlowSize: CGFloat = 22

    /// How much of a row a colour slider catches a drag in.
    ///
    /// Taller than the track it draws, by a lot, for the reason the crop handles
    /// have two sizes: the drawn control is what the eye aims at and this is what
    /// the hand can hit. Forty-four points is the smallest target a finger is
    /// expected to manage; a mouse does not need that much, and a row that size
    /// would push the other ten out of sight.
    #if os(iOS)
    static let colorSliderHitHeight: CGFloat = 44
    #else
    static let colorSliderHitHeight: CGFloat = 24
    #endif
}
