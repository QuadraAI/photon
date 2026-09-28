//
//  MediaSidebar.swift
//  Photon
//

import SwiftUI

/// The photos found under the window's folder, listed by name.
///
/// Names only, by design: a thumbnail grid is a different feature, and a `List`
/// keeps a folder of thousands cheap.
struct MediaSidebar: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if case .loaded(let photos) = editor.library, !photos.isEmpty {
                filterField
            }
            content
        }
    }

    // MARK: - Header

    /// A section header inside the list rather than a bar above it, so the
    /// `List` lines it up with the row content — the selection inset would
    /// otherwise leave it standing to the left of every row.
    private var header: some View {
        HStack(spacing: 6) {
            Text("editor.sidebar.title")

            Spacer(minLength: 0)

            // Follows the filter, so it doubles as feedback that the filter is
            // doing something.
            //
            // Drawn in a box the width of the window's sidebar toggle, pushed to
            // the same trailing edge, so the count reads as belonging to the
            // button above it — a number of any width stays on the button's axis.
            // The box is a plain container: put the identifier on it instead of
            // on the `Text` and the section header's row takes it, leaving the
            // count without an element of its own.
            HStack(spacing: 0) {
                Text(editor.visiblePhotos.count, format: .number)
                    .monospacedDigit()
                    .accessibilityIdentifier("editor.sidebar.count")
            }
            .frame(minWidth: AppLayout.sidebarToggleWidth, alignment: .center)
            .padding(.trailing, AppLayout.sidebarCountTrailingInset)
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch editor.library {
        case .loading:
            message("editor.sidebar.loading", systemImage: "hourglass") {
                ProgressView().controlSize(.small)
            }

        case .loaded(let photos) where photos.isEmpty:
            message("editor.sidebar.empty", systemImage: "photo.on.rectangle.angled")

        case .loaded:
            if editor.isFilteringToNothing {
                message("editor.sidebar.noMatch", systemImage: "magnifyingglass")
            } else {
                photoList
            }

        case .failed:
            message("editor.sidebar.failed", systemImage: "exclamationmark.triangle.fill") {
                Button("editor.sidebar.retry") {
                    Task { await editor.retry() }
                }
            }
        }
    }

    /// A plain field rather than `.searchable`: that modifier needs a navigation
    /// container or a toolbar to host it, and this sidebar has neither.
    private var filterField: some View {
        @Bindable var editor = editor

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("editor.sidebar.filter", text: $editor.filter)
                .textFieldStyle(.plain)
                .font(.callout)
                .accessibilityIdentifier("editor.sidebar.filter")

            if !editor.filter.isEmpty {
                Button {
                    editor.filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("editor.sidebar.filter.clear")
                .accessibilityIdentifier("editor.sidebar.filter.clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: .capsule)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - List

    private var photoList: some View {
        // A plain `List` with a selection binding rather than buttons with a
        // hand-painted highlight: this is what gives the native rounded
        // selection, the dimmed look when the window is inactive, hover
        // highlighting, and arrow-key navigation for free.
        List(selection: selectedID) {
            Section {
                ForEach(editor.visiblePhotos) { photo in
                    row(photo)
                        .tag(photo.id)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                }
            } header: {
                header
            }
        }
        .listStyle(.sidebar)
        // The list's own material is switched off so the sidebar draws one
        // surface across the filter field, the header and the rows. Left on, the
        // strip above the list stayed bare and showed the window's white.
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("editor.sidebar.list")
    }

    /// Selecting is deliberately not a plain assignment: the row is highlighted
    /// on the same frame, and the decode happens behind it.
    private var selectedID: Binding<URL?> {
        Binding(
            get: { editor.selection?.id },
            set: { id in
                guard let id, let photo = editor.visiblePhotos.first(where: { $0.id == id }) else {
                    return
                }
                editor.beginSelecting(photo)
            }
        )
    }

    private func row(_ photo: PhotoItem) -> some View {
        let hasSubfolder = !photo.subfolderPath.isEmpty
        // Past the accessibility sizes there is no room beside the name, so the
        // subfolder moves under it rather than falling off the row. It is how
        // two identically named photos are told apart, so losing it would be
        // information lost, not layout reflowed.
        let stacks = dynamicTypeSize.isAccessibilitySize

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: photo.symbolName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: AppLayout.sidebarGlyphWidth)
                    .accessibilityHidden(true)

                name(photo)
                    .layoutPriority(1)

                if hasSubfolder, !stacks {
                    Spacer(minLength: 6)
                    subfolder(photo)
                }
            }

            if hasSubfolder, stacks {
                subfolder(photo)
                    .padding(.leading, AppLayout.sidebarGlyphWidth + 6)
            }
        }
        .tooltip(photo.subfolderPath)
        // One element per row, so VoiceOver reads "delta.jpg, Subfolder" as a
        // single item instead of two — and so the identifier below applies to
        // the row rather than being pushed onto each of its children.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.sidebar.row.\(photo.name)")
    }

    /// Name at full strength and extension dimmed, so the extensions line up in
    /// a column. Two `Text`s rather than one concatenated with `+`, which is
    /// deprecated, and which would also send the pair through the string catalog
    /// as a format.
    private func name(_ photo: PhotoItem) -> some View {
        HStack(spacing: 0) {
            Text(photo.baseName)
            Text(photo.fileExtension)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// Shown on the row, not only in the tooltip: a tooltip is undiscoverable,
    /// and iPadOS has no hover at all.
    private func subfolder(_ photo: PhotoItem) -> some View {
        Text(photo.subfolderPath)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // MARK: - States

    private func message(
        _ key: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Attaches a hover tooltip only when there is something worth saying.
    @ViewBuilder func tooltip(_ text: String) -> some View {
        if text.isEmpty {
            self
        } else {
            help(text)
        }
    }
}
