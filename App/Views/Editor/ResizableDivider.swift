//
//  ResizableDivider.swift
//  Photon
//

import SwiftUI

/// The invisible grab area between two panes.
///
/// Draws nothing: the panes' own surfaces meeting is the separation, and a drawn
/// line between two sheets of glass reads as a seam rather than a divider.
struct ResizableDivider: View {
    @Binding var width: CGFloat

    let range: ClosedRange<CGFloat>

    /// Which way the pane grows as the pointer moves: +1 when the pane is on the
    /// leading side of the handle, -1 when it is on the trailing side.
    let dragSign: CGFloat

    let label: LocalizedStringKey
    let identifier: String

    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: AppLayout.dividerHitWidth)
            .contentShape(.rect)
            .resizePointer()
            .gesture(drag)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text(width, format: .number.precision(.fractionLength(0))))
            .accessibilityAdjustableAction(adjust)
            .accessibilityIdentifier(identifier)
    }

    /// `.global`, not the default `.local`. The handle itself moves as the pane
    /// resizes, so a local coordinate space feeds the drag's own movement back
    /// into the width and the layout never settles — which hangs the window.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? width
                if widthAtDragStart == nil {
                    widthAtDragStart = start
                }
                width = (start + value.translation.width * dragSign).clamped(to: range)
            }
            .onEnded { _ in
                widthAtDragStart = nil
            }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let step: CGFloat = 16
        switch direction {
        case .increment:
            width = (width + step).clamped(to: range)
        case .decrement:
            width = (width - step).clamped(to: range)
        @unknown default:
            break
        }
    }
}

private extension View {
    /// The resize cursor. `pointerStyle` is macOS-only; iPadOS has no pointer.
    @ViewBuilder func resizePointer() -> some View {
        #if os(macOS)
        pointerStyle(.columnResize)
        #else
        self
        #endif
    }
}
