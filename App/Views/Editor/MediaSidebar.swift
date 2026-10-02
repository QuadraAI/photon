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

    /// The folder that is open, as the window's title gives it.
    ///
    /// Handed in rather than read from the environment: the sidebar is a pane of
    /// the editor, and the folder is the editor's, not something it owns.
    let folderName: String

    /// The folders the user has opened, by their path. Kept here rather than in
    /// the tree, so a filter or another folder does not close them.
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if editor.foundCount > 0 {
                filterField
                header
            }
            content
        }
    }

    // MARK: - Header

    /// The folder that is open, and how many of its photos are on show.
    ///
    /// A bar above the list rather than a header inside it, so it holds its place
    /// while the rows scroll past underneath — the same way the filter field above
    /// it does. A section header pinned to the top of a scrolling list is a thing
    /// the rows move under; this is the answer to "what am I looking at", and it
    /// should no more travel than the name of the folder in the window's title.
    ///
    /// It carries the count rather than the list, so a filter reads as having
    /// done something.
    private var header: some View {
        HStack(spacing: 6) {
            Text(folderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                // The end of a folder's name is the part that tells it apart:
                // every frame in a card is called DSC0…, and the last few
                // characters are what differ.
                .truncationMode(.middle)

            Spacer(minLength: 6)

            // Drawn in a box the width of the window's sidebar toggle, pushed to
            // the same trailing edge, so the count reads as belonging to the
            // button above it — a number of any width stays on the button's axis.
            // The box is a plain container: put the identifier on it instead of
            // on the `Text` and the header's row takes it, leaving the count
            // without an element of its own.
            HStack(spacing: 0) {
                Text(editor.matches.count, format: .number)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.sidebar.count")
            }
            .frame(minWidth: AppLayout.sidebarToggleWidth, alignment: .center)
            .padding(.trailing, AppLayout.sidebarCountTrailingInset)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
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
        //
        // It lists a tree, because a `List` lays out every row it is handed:
        // folded up, a folder of thousands is a single row.
        List(selection: selectedPhoto) {
            ForEach(editor.nodes) { node in
                switch node {
                case .folder(let folder):
                    FolderRows(expanded: $expanded, folder: folder)
                case .photo(let photo):
                    PhotoRow(photo: photo).listed
                }
            }
        }
        .listStyle(.sidebar)
        // The list's own material is switched off so the sidebar draws one
        // surface across the filter field, the header and the rows. Left on,
        // the strip above the list stayed bare and showed the window's white.
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("editor.sidebar.list")
    }

    /// Selecting is deliberately not a plain assignment: the row is highlighted
    /// on the same frame, and the decode happens behind it.
    private var selectedPhoto: Binding<URL?> {
        Binding(
            get: { editor.selection?.id },
            set: { id in
                // A folder's row carries its own URL, and choosing one is not
                // choosing a photo.
                guard let id, let photo = editor.photo(withNodeID: id) else { return }
                editor.beginSelecting(photo)
            }
        )
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

/// A folder's rows: what is inside it, and whether it is open.
///
/// A view type rather than a function because it recurses, and Swift cannot infer
/// the type of a recursive `some View`.
private struct FolderRows: View {
    @Binding var expanded: Set<String>
    let folder: LibraryNode.Folder

    var body: some View {
        DisclosureGroup(isExpanded: isOpen) {
            ForEach(folder.children) { child in
                switch child {
                case .folder(let subfolder):
                    FolderRows(expanded: $expanded, folder: subfolder)
                case .photo(let photo):
                    PhotoRow(photo: photo).listed
                }
            }
        } label: {
            label
                .contentShape(.rect)
                // The name opens the folder as well as the triangle does.
                .onTapGesture { isOpen.wrappedValue.toggle() }
        }
    }

    /// A folder's row: its glyph, its name, and how many photos are in it and
    /// below it.
    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.sidebarGlyphWidth)
                .accessibilityHidden(true)

            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text(folder.photoCount, format: .number)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.sidebar.folder.\(folder.path)")
    }

    private var isOpen: Binding<Bool> {
        Binding(
            get: { expanded.contains(folder.path) },
            set: { open in
                if open {
                    expanded.insert(folder.path)
                } else {
                    expanded.remove(folder.path)
                }
            }
        )
    }
}

/// A photo's row: a glyph for its kind, then its name with the extension dimmed
/// so the extensions line up in a column.
private struct PhotoRow: View {
    let photo: PhotoItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: photo.symbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.sidebarGlyphWidth)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text(photo.baseName)
                Text(photo.fileExtension)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        // One element per row, so VoiceOver reads the name and its extension as
        // a single item — and so the identifier below applies to the row rather
        // than being pushed onto each of its children.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.sidebar.row.\(photo.name)")
    }
}

private extension PhotoRow {
    /// As the list wants it: selectable, and inset like the folder rows.
    var listed: some View {
        tag(photo.id)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
    }
}
