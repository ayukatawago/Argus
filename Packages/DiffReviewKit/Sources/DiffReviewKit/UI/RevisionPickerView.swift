import SwiftUI

/// Base/head ref pickers plus the "include uncommitted changes" toggle and refresh button, shown
/// atop the commit sidebar (`CommitListView`). Stacked vertically to fit the sidebar's width.
struct RevisionPickerView: View {
    @Bindable var model: DiffReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            refPicker(title: "Base", selection: $model.baseRef)
            refPicker(title: "Head", selection: $model.headRef)
            HStack {
                Toggle("Include uncommitted", isOn: $model.includeUncommitted)
                    .onChange(of: model.includeUncommitted) {
                        Task { await model.refreshDiff() }
                    }
                    .font(.caption)

                Spacer()

                if model.isLoadingDiff {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh diff")
                }
            }
        }
        .padding(8)
    }

    private func refPicker(title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            TextField(title, text: selection)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.reload() } }
            if !model.availableRefs.isEmpty {
                Menu {
                    ForEach(model.availableRefs, id: \.self) { ref in
                        Button(ref) {
                            selection.wrappedValue = ref
                            Task { await model.reload() }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
    }
}
