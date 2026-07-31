import SwiftUI

/// Base/head ref pickers plus the "include uncommitted changes" toggle shown above the diff pane.
struct RevisionPickerView: View {
    @Bindable var model: DiffReviewModel

    var body: some View {
        HStack(spacing: 12) {
            refPicker(title: "Base", selection: $model.baseRef)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            refPicker(title: "Head", selection: $model.headRef)

            Toggle("Include uncommitted", isOn: $model.includeUncommitted)
                .onChange(of: model.includeUncommitted) {
                    Task { await model.refreshDiff() }
                }

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
        .padding(8)
    }

    private func refPicker(title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, text: selection)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)
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
