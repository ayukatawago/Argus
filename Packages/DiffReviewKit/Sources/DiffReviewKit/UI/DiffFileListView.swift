import SwiftUI

/// The diff pane: every changed file stacked in one lazy scroll, each under a pinned header. This view
/// owns the only ⌘F and ⌘C shortcuts and the search bar. Each file's rows are emitted straight into the
/// lazy stack from its memoized layout, and the list body reads no interaction state.
struct DiffFileListView: View {
    let model: DiffReviewModel
    @Bindable var interaction: DiffInteractionState

    /// Coordinate space of the lazy stack, shared by code cell frames and the drag gestures.
    static let rowSpace = "diffRows"

    static func headerID(for filePath: String) -> String {
        "\(filePath)|file"
    }

    var body: some View {
        ScrollViewReader { proxy in
            let scroller = DiffListScroller(model: model, proxy: proxy)
            VStack(spacing: 0) {
                DiffSearchBar(model: model, interaction: interaction, scroller: scroller)
                // Outside the lazy stack, so it is never discarded once scrolled far off screen.
                DiffScrollRequestHandler(interaction: interaction, scroller: scroller)
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.files) { file in
                            fileSection(file)
                        }
                    }
                    .coordinateSpace(name: Self.rowSpace)
                    .onPreferenceChange(CodeCellFramesKey.self) { frames in
                        // SwiftUI delivers preference changes on the main thread.
                        MainActor.assumeIsolated {
                            interaction.cellFrames.frames = frames
                        }
                    }
                    .onPreferenceChange(GutterFramesKey.self) { frames in
                        MainActor.assumeIsolated {
                            interaction.cellFrames.gutterFrames = frames
                        }
                    }
                    .simultaneousGesture(dragSelectGesture)
                    .simultaneousGesture(tapSelectGesture)
                }
            }
        }
        .background {
            DiffShortcutButtons(interaction: interaction, copy: copySelection)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func fileSection(_ file: DiffFile) -> some View {
        let isCollapsed = model.collapsedFilePaths.contains(file.path)
        Section {
            if !isCollapsed {
                fileRows(file)
            }
        } header: {
            fileHeader(file, isCollapsed: isCollapsed)
        }
    }

    /// The file's rows, emitted directly as lazy children of the stack. A hunkless file shows the
    /// "no line-level changes" message instead.
    @ViewBuilder
    private func fileRows(_ file: DiffFile) -> some View {
        if file.isBinaryOrHunkless {
            Text("No line-level changes to display (binary file, rename, or mode-only change).")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            let layout = model.layout(for: file)
            ForEach(layout.items) { item in
                DiffRowView(item: item, file: file, layout: layout, model: model, interaction: interaction)
            }
        }
    }

    private func fileHeader(_ file: DiffFile, isCollapsed: Bool) -> some View {
        DiffFileHeaderView(
            file: file,
            isViewed: model.viewedFiles[file.path] != nil,
            isCollapsed: isCollapsed,
            commentCount: model.comments(for: file.path).count,
            onToggleCollapsed: {
                model.toggleCollapsed(file.path)
                interaction.requestScroll(to: file.path)
            },
            onToggleViewed: {
                model.toggleViewed(file.path)
                interaction.requestScroll(to: file.path)
            }
        )
        .id(Self.headerID(for: file.path))
    }

    /// The layout of the file at `filePath`, if it is still in the diff.
    func layout(forPath filePath: String) -> DiffFileLayout? {
        model.files.first { $0.path == filePath }.map { model.layout(for: $0) }
    }
}

/// Scrolls the list to a file header or to a row. Built inside each `ScrollViewReader` pass.
@MainActor
struct DiffListScroller {
    let model: DiffReviewModel
    let proxy: ScrollViewProxy

    func scrollToHeader(_ filePath: String) {
        proxy.scrollTo(DiffFileListView.headerID(for: filePath), anchor: .top)
    }

    /// Scrolls straight to the row when it is in the file the list is already on. Otherwise (another
    /// file, or a collapsed one) the file's header is scrolled to first, since its rows may not be
    /// rendered yet, and then, on the next runloop turn, the row itself. `previousFilePath` is the file
    /// of the match being stepped away from, `nil` when there is none.
    func reveal(_ ref: RowRef, previousFilePath: String?) {
        let isCollapsed = model.collapsedFilePaths.contains(ref.filePath)
        if !isCollapsed, ref.filePath == previousFilePath {
            proxy.scrollTo(ref.rowID, anchor: .center)
            return
        }
        if isCollapsed {
            model.expandFile(ref.filePath)
        }
        scrollToHeader(ref.filePath)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                proxy.scrollTo(ref.rowID, anchor: .center)
            }
        }
    }
}

/// Carries out a scroll request from the file tree or a Viewed/collapse toggle. It is a view of its own
/// so that its `onChange` reads the request here, not in the list body. It sits outside the lazy stack.
private struct DiffScrollRequestHandler: View {
    let interaction: DiffInteractionState
    let scroller: DiffListScroller

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onChange(of: interaction.scrollRequest) { _, request in
                if let request {
                    scroller.scrollToHeader(request.filePath)
                }
            }
    }
}

/// The ⌘C and ⌘F shortcuts. They are hidden buttons, so they exist once for the whole list.
private struct DiffShortcutButtons: View {
    let interaction: DiffInteractionState
    let copy: () -> Void

    var body: some View {
        Button("") {
            copy()
        }
        .keyboardShortcut("c", modifiers: .command)
        .disabled(interaction.pendingSelection == nil && interaction.textSelection == nil)
        .opacity(0)
        .allowsHitTesting(false)

        Button("") {
            interaction.openSearch()
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .allowsHitTesting(false)
    }
}
