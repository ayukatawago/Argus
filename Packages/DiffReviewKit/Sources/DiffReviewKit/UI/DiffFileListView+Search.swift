import SwiftUI

/// The ⌘F bar. It renders nothing while search is closed. The match list is recomputed only when the
/// query changes or the layout revision does, never per row.
struct DiffSearchBar: View {
    let model: DiffReviewModel
    @Bindable var interaction: DiffInteractionState
    let scroller: DiffListScroller

    @FocusState private var fieldFocused: Bool

    var body: some View {
        if interaction.isSearching {
            VStack(spacing: 0) {
                bar
                Divider()
            }
            .onAppear {
                fieldFocused = true
                interaction.refreshSearchMatches(sections: sections)
            }
            .onChange(of: interaction.searchFocusToken) {
                fieldFocused = true
            }
            .onChange(of: interaction.searchQuery) {
                if let first = interaction.searchQueryChanged(sections: sections) {
                    scroller.reveal(first, previousFilePath: nil)
                }
            }
            .onChange(of: model.layoutRevision) {
                interaction.refreshSearchMatches(sections: sections)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in diff", text: $interaction.searchQuery)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit { step(1) }
                .onExitCommand { interaction.closeSearch() }
            if !interaction.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(counterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(interaction.search.matches.isEmpty)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(interaction.search.matches.isEmpty)
            Button {
                interaction.closeSearch()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var counterText: String {
        guard !interaction.search.matches.isEmpty else { return "No matches" }
        return "\(interaction.search.currentIndex + 1) of \(interaction.search.matches.count)"
    }

    /// Every file's rows, memoized by the model. Read only in the callbacks above, never in a body.
    private var sections: [DiffRowSection] {
        model.files.map { DiffRowSection(filePath: $0.path, items: model.layout(for: $0).items) }
    }

    private func step(_ delta: Int) {
        let previousFilePath = interaction.search.currentMatch?.filePath
        if let ref = interaction.stepSearch(delta) {
            scroller.reveal(ref, previousFilePath: previousFilePath)
        }
    }
}
