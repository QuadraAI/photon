//
//  ExportSheet.swift
//  Photon
//

import SwiftUI
import UniformTypeIdentifiers

/// The one place an export is described: name, folder, format, quality and the
/// two metadata choices, with the result or the failure in the same sheet.
///
/// A custom sheet rather than a save panel because the options belong together:
/// a system panel can own the folder and the name, but not the format-specific
/// quality, the GPS switch and the output size without splitting them across two
/// dialogs.
struct ExportSheet: View {
    @Bindable var model: ExportViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isChoosingFolder = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(macOS)
        .frame(
            width: Metrics.width,
            height: model.exportedPhoto == nil ? Metrics.height : Metrics.successHeight
        )
        #endif
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            model.setFolder(url)
        }
        .fileDialogDefaultDirectory(model.folder)
        .fileDialogConfirmationLabel(Text("export.folder.use"))
        .fileDialogMessage(Text("export.folder.message"))
        .interactiveDismissDisabled(model.isExporting)
        .onAppear {
            #if os(macOS)
            isNameFocused = true
            #endif
        }
        .onDisappear { model.close() }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("export.title")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("export.title")

            Text(verbatim: model.photo.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        if let exported = model.exportedPhoto {
            success(exported)
        } else {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    destination
                    Divider()
                    options
                    Divider()
                    output
                    if let failure = model.failure {
                        error(failure)
                    }
                }
                .padding(20)
                .disabled(model.isExporting)
            }

            Divider()
            footer
        }
    }

    // MARK: - Destination

    private var destination: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("export.name") {
                HStack(spacing: 6) {
                    TextField("export.name.placeholder", text: $model.baseName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .accessibilityLabel("export.name")
                        .accessibilityValue(Text(verbatim: model.fileName ?? ""))
                        .accessibilityIdentifier("export.name")

                    Text(verbatim: "." + model.format.fileExtension)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                if let fileName = model.fileName {
                    Text("export.savesAs \(fileName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Label("export.invalidName", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("export.collision.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("export.folder") {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(verbatim: model.folderName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(Text(verbatim: model.folder.path(percentEncoded: false)))

                    Spacer(minLength: 8)

                    Button("export.folder.choose") {
                        isChoosingFolder = true
                    }
                    .accessibilityLabel("export.folder.choose")
                    .accessibilityHint("export.folder.hint")
                    .accessibilityIdentifier("export.folder.choose")
                }
            }

            field("export.format") {
                Picker("export.format", selection: $model.format) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("export.format")
                .accessibilityIdentifier("export.format")
            }
        }
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("export.quality")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    if model.format.isLossy {
                        Text(model.quality, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("export.lossless")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.format.isLossy {
                    Slider(value: $model.quality, in: ExportOptions.qualityRange, step: Metrics.qualityStep)
                        .accessibilityLabel("export.quality")
                        .accessibilityValue(Text(model.quality, format: .percent.precision(.fractionLength(0))))
                        .accessibilityIdentifier("export.quality")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("export.removeLocation", isOn: $model.removeLocation)
                    .accessibilityLabel("export.removeLocation")
                    .accessibilityHint("export.removeLocation.hint")
                    .accessibilityIdentifier("export.removeLocation")

                Text("export.removeLocation.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Output

    private var output: some View {
        field("export.output", spacing: 8) {
            HStack(spacing: 4) {
                Text("export.dimensions")
                    .foregroundStyle(.secondary)
                Text(model.outputWidth, format: .number)
                    .monospacedDigit()
                Text(verbatim: "×")
                Text(model.outputHeight, format: .number)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("export.dimensions")

            if model.hasUnappliedCrop {
                Label("export.unappliedCrop", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("export.unappliedCrop")
            }
        }
    }

    /// A titled row. The title is visual only; the control beneath carries the
    /// accessibility label.
    private func field<Content: View>(
        _ title: LocalizedStringKey,
        spacing: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            content()
        }
    }

    private func error(_ failure: PhotoExportError) -> some View {
        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("export.error")
    }

    // MARK: - Footer

    private var footer: some View {
        footerLayout {
            if model.isExporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("export.progress")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("export.progress")
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button("export.cancel") {
                    if model.isExporting {
                        model.cancel()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("export.cancel")

                Button("export.action") {
                    model.export()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .accessibilityIdentifier("export.action")
            }
        }
        .padding(20)
    }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    // MARK: - Success

    private func success(_ exported: ExportedPhoto) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("export.success.title")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: exported.url.lastPathComponent)
                .font(.headline)
                .multilineTextAlignment(.center)

            successDetailsLayout {
                Label(dimensionsText(exported.pixelSize), systemImage: "aspectratio")
                Label(exported.byteCount.formatted(.byteCount(style: .file)), systemImage: "doc")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("export.open") {
                    open(exported.url)
                }
                .accessibilityIdentifier("export.open")

                Spacer(minLength: 0)

                Button("export.done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("export.done")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Hands the finished file to the system.
    ///
    /// On macOS `NSWorkspace` is what works from a sandbox with a user-selected
    /// file; on iPadOS the SwiftUI action opens it in the appropriate app.
    private func open(_ url: URL) {
        #if os(macOS)
        if !FileOpener.open(url) {
            openURL(url)
        }
        #else
        openURL(url)
        #endif
    }

    /// Dimensions and file size side by side, or stacked when the text is too
    /// large for two labels on one line.
    private var successDetailsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    /// Dimensions as one locale-aware line: "6000 × 4000".
    private func dimensionsText(_ size: CGSize) -> String {
        let width = Int(size.width.rounded()).formatted(.number)
        let height = Int(size.height.rounded()).formatted(.number)
        return "\(width) × \(height)"
    }

    /// Fixed dimensions the sheet opens at on macOS, and the quality step.
    private enum Metrics {
        static let width: CGFloat = 520
        static let height: CGFloat = 620
        static let successHeight: CGFloat = 420
        static let qualityStep = 0.05
    }
}
