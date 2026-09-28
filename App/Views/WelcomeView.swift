//
//  WelcomeView.swift
//  Photon
//

import SwiftUI

/// Shown when no folder is open: the first screen on a fresh install, and the
/// fallback whenever a remembered folder could not be reopened.
struct WelcomeView: View {
    @Environment(FolderViewModel.self) private var folder

    /// Why a remembered folder was not reopened, when there was one.
    let notice: WelcomeNotice?

    var body: some View {
        VStack(spacing: 0) {
            SettingsMenus()
            content
        }
        .background(.background)
    }

    /// How far above true centre the content sits, as a fraction of the
    /// available height. Optical centring: a block this small reads as low when
    /// it is centred mathematically.
    private static let centreLift = 0.1

    /// Sits slightly above centre, and still scrolls so the layout survives the
    /// largest Dynamic Type sizes without clipping.
    private var content: some View {
        GeometryReader { proxy in
            // Extra *bottom* padding, not an `offset`: padding takes part in
            // layout, so the centring frame below splits it and the visible
            // content genuinely moves up. An offset would draw content outside a
            // frame with no room for it, clipping at accessibility text sizes.
            let lift = proxy.size.height * Self.centreLift

            ScrollView {
                VStack(spacing: 32) {
                    header

                    if let notice {
                        noticeBanner(for: notice)
                    }

                    chooseFolderButton
                }
                .frame(maxWidth: AppLayout.contentColumnWidth)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 40 + lift * 2)
                // `minHeight`, not a fixed height: the content sits above centre
                // while it fits, and overflows into scrolling when it does not.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            AppMark()

            Text("welcome.title")
                .font(.largeTitle.bold())

            Text("welcome.subtitle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var chooseFolderButton: some View {
        VStack(spacing: 12) {
            Button { folder.chooseFolder() } label: {
                // `minWidth` rather than `maxWidth`: the label has to stay free
                // to grow with Dynamic Type instead of truncating.
                Label("welcome.chooseFolder", systemImage: "folder.badge.plus")
                    .frame(minWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(folder.folderPick == .opening)
            .accessibilityHint("welcome.chooseFolder.hint")
            .accessibilityIdentifier("welcome.chooseFolder")

            if folder.folderPick == .opening {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("welcome.opening")
            }
        }
    }

    /// Inline and non-blocking on purpose. An alert here would steal focus at
    /// launch, before the user knows where they are.
    private func noticeBanner(for notice: WelcomeNotice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(notice.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Button("welcome.notice.forget") { folder.forgetRememberedFolder() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
