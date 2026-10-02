//
//  Comparable+Clamped.swift
//  Photon
//

import Foundation

extension Comparable {
    /// Keeps a value inside `range`.
    ///
    /// Used by the resizable panes, where clamping at the point of assignment
    /// matters: a drag pulled far past a limit and back must not leave the width
    /// lagging behind the pointer.
    ///
    /// `nonisolated` because the engine clamps too — the colour cast's channel
    /// gains are worked out on the editor's actor — and arithmetic has no reason
    /// to belong to the main actor.
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
