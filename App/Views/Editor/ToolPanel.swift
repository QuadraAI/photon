//
//  ToolPanel.swift
//  Photon
//

import SwiftUI

/// The open tool's panel, shown to the left of the rail.
///
/// The chrome, heading and behaviour are real. The crop tool's controls are real
/// too; the other tools are still placeholders until the adjustments they name
/// exist to be adjusted.
struct ToolPanel: View {
    @Environment(EditorViewModel.self) private var editor

    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tool.name)
                .font(.headline)
                .padding(16)
                .accessibilityIdentifier("editor.toolPanel.title")

            Divider()

            content
        }
        .frame(width: editor.panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        // No background of its own: the panel and its resize handle share one
        // glass surface, drawn by the group that holds them.
        // The identifier lives on the heading, not the panel: a container's
        // identifier is pushed down onto its children and would replace it.
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case .crop:
            CropPanel()
        case .color:
            ColorPanel()
        case .light, .presets:
            VStack(alignment: .leading, spacing: 0) {
                Text("tool.panel.comingSoon")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)

                Spacer(minLength: 0)
            }
        }
    }
}
