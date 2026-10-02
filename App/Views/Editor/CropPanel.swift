//
//  CropPanel.swift
//  Photon
//

import SwiftUI

/// The crop tool's controls.
///
/// Every crop the overlay can make is makeable from here. That is not a nicety:
/// the overlay is eight drag targets, and a drag target is not something
/// VoiceOver, Switch Control or Voice Control can operate. The panel is the
/// accessible path, so it carries the shapes, the turn, and each edge as a
/// control that can be adjusted without a pointer.
///
/// The panel edits a *draft*. Nothing here reaches the history until Done — which
/// is what makes Escape free, and what makes a minute of fiddling one step to
/// undo rather than fifty.
struct CropPanel: View {
    @Environment(EditorViewModel.self) private var editor

    /// The custom pair's two fields.
    ///
    /// Local to the panel: a pair of numbers is how a ratio is *entered*, and the
    /// crop holds the ratio it produced. Restoring them from the crop would mean
    /// deciding which preset a custom pair had come from, which is not knowable.
    @State private var customWidth = 16
    @State private var customHeight = 9

    /// Whether the custom fields are showing.
    @State private var isCustomising = false

    /// Furthest an edge may be pulled in, as a fraction of the frame.
    ///
    /// Not a half: a crop can sit well over to one side, and the opposite edge's
    /// control is what brings it back. Capping at a half would make the right
    /// half of a photo unreachable except by dragging.
    private static let insetRange: ClosedRange<Double> = 0...1
    private static let insetStep = 0.01

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("tool.crop.ratio.title")
                    ratios
                    if isCustomising { customFields }

                    Divider().padding(.top, 12)

                    section("tool.crop.transform.title")
                    transform

                    Divider().padding(.top, 12)

                    section("tool.crop.edges.title")
                    edges
                }
                .padding(.bottom, 12)
            }

            Divider()
            actions
        }
        // No background of its own: the panel and its resize handle share one
        // glass surface, drawn by the group that holds them.
    }

    // MARK: - Ratios

    private var ratios: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AspectRatio.presets, id: \.identifier) { ratio in
                ratioRow(ratio)
            }
            ratioRow(nil)
        }
    }

    /// A ratio the user can pick, or — with `nil` — the custom pair.
    private func ratioRow(_ ratio: AspectRatio?) -> some View {
        let isSelected = ratio.map { editor.cropAspect == $0 } ?? isUsingCustomRatio
        let title = ratio?.text ?? Text("tool.crop.ratio.custom")
        let identifier = ratio?.identifier ?? "custom"

        return Button {
            if let ratio {
                isCustomising = false
                editor.setCropAspect(ratio)
            } else {
                isCustomising.toggle()
                if isCustomising { applyCustom() }
            }
        } label: {
            HStack(spacing: 8) {
                // A checkmark as well as the tint, so which ratio is on is not
                // carried by colour alone.
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                    .accessibilityHidden(true)

                title
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("tool.crop.ratio.\(identifier)")
    }

    private var isUsingCustomRatio: Bool {
        guard let aspect = editor.cropAspect else { return false }
        return !AspectRatio.presets.contains(aspect)
    }

    private var customFields: some View {
        HStack(spacing: 6) {
            TextField("tool.crop.custom.width", value: $customWidth, format: .number)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 52)
                .accessibilityLabel("tool.crop.custom.width")

            Text(verbatim: ":")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("tool.crop.custom.height", value: $customHeight, format: .number)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 52)
                .accessibilityLabel("tool.crop.custom.height")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .onChange(of: customWidth) { applyCustom() }
        .onChange(of: customHeight) { applyCustom() }
    }

    /// Applies the pair, ignoring anything that is not a ratio.
    ///
    /// An `Int` field keeps the last value that parsed, so a half-typed number
    /// never arrives here — but a zero or a negative still can, and neither is a
    /// ratio. The crop keeps the one it had until the fields say something legal.
    private func applyCustom() {
        guard customWidth > 0, customHeight > 0 else { return }
        editor.setCropAspect(.ratio(customWidth, customHeight))
    }

    // MARK: - Turning

    private var transform: some View {
        HStack(spacing: 8) {
            Button {
                editor.rotateCrop(clockwise: false)
            } label: {
                Label("tool.crop.rotate.left", systemImage: "rotate.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 24)
            }
            .help("tool.crop.rotate.left")
            .accessibilityLabel("tool.crop.rotate.left")
            .accessibilityIdentifier("tool.crop.rotate.left")

            Button {
                editor.rotateCrop(clockwise: true)
            } label: {
                Label("tool.crop.rotate.right", systemImage: "rotate.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 24)
            }
            .help("tool.crop.rotate.right")
            .accessibilityLabel("tool.crop.rotate.right")
            .accessibilityIdentifier("tool.crop.rotate.right")

            Button {
                editor.swapCropOrientation()
            } label: {
                Label("tool.crop.swap", systemImage: "arrow.2.squarepath")
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 24)
            }
            .help("tool.crop.swap")
            .disabled(!canSwap)
            .accessibilityLabel("tool.crop.swap")
            .accessibilityHint("tool.crop.swap.hint")
            .accessibilityIdentifier("tool.crop.swap")

            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    /// Only a pair of numbers can be exchanged. A free crop is held to nothing
    /// and the photo's own shape follows the frame, so neither has a side to turn
    /// over — the button is disabled rather than quietly doing nothing.
    private var canSwap: Bool {
        guard let aspect = editor.cropAspect else { return false }
        if case .fixed = aspect { return true }
        return false
    }

    // MARK: - Edges

    private var edges: some View {
        VStack(alignment: .leading, spacing: 0) {
            edgeRow(.top, label: "tool.crop.edge.top", identifier: "top")
            edgeRow(.bottom, label: "tool.crop.edge.bottom", identifier: "bottom")
            edgeRow(.left, label: "tool.crop.edge.left", identifier: "left")
            edgeRow(.right, label: "tool.crop.edge.right", identifier: "right")
        }
        .disabled(!editor.isCropping)
    }

    /// One edge, as an inset from its own side of the frame.
    ///
    /// A stepper rather than a slider: it is natively adjustable, so VoiceOver,
    /// Switch Control and Full Keyboard Access all drive it without this view
    /// having to invent an adjustable element — and a percentage readout beside
    /// it gives the operation a value to speak.
    ///
    /// The value is *read back* from the crop rather than stored, because a
    /// locked ratio ties the axes together: pulling the left edge in on a 16:9
    /// crop moves the top and bottom too, and a control holding its own copy
    /// would drift away from what is on the canvas.
    private func edgeRow(
        _ edge: CropGeometry.Edges,
        label: LocalizedStringKey,
        identifier: String
    ) -> some View {
        let inset = editor.cropInset(edge)
        // A `String` for the value spoken aloud, and the format overload for the
        // one drawn: the drawn one resolves its locale from the environment, so
        // it follows the app's language rather than the system's.
        let percentage: String = Double(inset).formatted(.percent.precision(.fractionLength(0)))

        return HStack(spacing: 8) {
            Text(label)
                .font(.callout)

            Spacer(minLength: 0)

            Text(Double(inset), format: .percent.precision(.fractionLength(0)))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { Double(editor.cropInset(edge)) },
                    set: { editor.setCropInset(edge, to: CGFloat($0)) }
                ),
                in: Self.insetRange,
                step: Self.insetStep
            ) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(label)
            .accessibilityValue(percentage)
            .accessibilityIdentifier("tool.crop.edge.\(identifier)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("tool.crop.reset") {
                editor.resetCrop()
            }
            .accessibilityHint("tool.crop.reset.hint")
            .accessibilityIdentifier("tool.crop.reset")

            Spacer(minLength: 0)

            // Escape. Both shortcuts work without the control being focused,
            // which is what makes them the keyboard equivalent of the overlay's
            // two exits rather than two more buttons.
            Button("tool.crop.cancel") {
                editor.abandonCropSession()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("tool.crop.cancel")

            // Return, and the same thing as clicking the crop icon again.
            Button("tool.crop.done") {
                editor.commitCropSession()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tool.crop.done")
        }
        .padding(12)
    }

    // MARK: - Presentation

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
