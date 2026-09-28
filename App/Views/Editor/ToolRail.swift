//
//  ToolRail.swift
//  Photon
//

import SwiftUI

/// The editor's right-hand rail: always visible, always icons only.
///
/// Clicking a tool opens its panel to the rail's left, so the rail is the one
/// piece of the editor that never moves.
struct ToolRail: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases) { tool in
                button(for: tool)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(width: AppLayout.toolRailWidth)
        // No identifier on the rail itself: SwiftUI pushes a container's
        // accessibility identifier down onto its children, which would overwrite
        // each button's own and leave all five unaddressable.
    }

    private func button(for tool: Tool) -> some View {
        let isOpen = editor.openTool == tool

        return Button {
            editor.toggleTool(tool)
        } label: {
            // A `Label` in icon-only style rather than a bare `Image`: an image
            // label leaves the control exposed as an image, not a button, so
            // neither VoiceOver nor the UI tests would find a control here.
            Label(tool.name, systemImage: tool.symbolName)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOpen ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .help(tool.name)
        .accessibilityLabel(tool.name)
        .accessibilityHint(isOpen ? "tool.panel.close.hint" : "tool.panel.open.hint")
        .accessibilityIdentifier("editor.tools.\(tool.rawValue)")
    }
}
