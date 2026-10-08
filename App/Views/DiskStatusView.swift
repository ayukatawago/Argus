import AppKit
import Monitors
import SwiftUI

struct DiskStatusView: View {
    @ObservedObject var store: DiskMonitorStore
    @ObservedObject var scanner: DiskCleanupScanner
    @State private var showingConfirmation = false
    @State private var showingRepoConfirmation = false
    @State private var hideSmall = true
    @State private var sortOrder = SortOrder.size
    @State private var copiedCandidateID: URL?

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case size = "Size"
    }

    private var visibleCandidates: [CleanupCandidate] {
        CleanupCandidateList.visible(
            scanner.candidates,
            hideSmall: hideSmall,
            sortedBy: sortOrder == .name ? CleanupCandidateList.byName : CleanupCandidateList.bySizeDescending
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            diskGauge
            Divider()
            cleanupSection
        }
        .padding()
        .frame(minWidth: 500, minHeight: 460)
        .alert("Remove Items?", isPresented: $showingConfirmation) {
            Button("Remove", role: .destructive) {
                // Git checkouts get a second, repo-naming confirmation: deleting one can lose
                // commits and branches that exist nowhere else.
                if pendingRemovals.contains(where: \.isGitRepository) {
                    showingRepoConfirmation = true
                } else {
                    removePending()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "These items will be permanently deleted. This cannot be undone.\n\n"
                    + pendingRemovals.map(\.displayName).joined(separator: "\n"))
        }
        .alert("Delete Git Repositories?", isPresented: $showingRepoConfirmation) {
            Button("Delete Repositories", role: .destructive) { removePending() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Unpushed commits, stashes and uncommitted changes in these repositories will be lost:\n\n"
                    + pendingRemovals.filter(\.isGitRepository).map(\.displayName).joined(separator: "\n"))
        }
        .alert(
            "Some Items Couldn't Be Removed",
            isPresented: Binding(
                get: { scanner.removalFailureMessage != nil },
                set: { if !$0 { scanner.removalFailureMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanner.removalFailureMessage ?? "")
        }
    }

    /// Exactly what the Remove button would delete now: selected, visible under the current
    /// filter, and passing the safety check.
    private var pendingRemovals: [CleanupCandidate] {
        scanner.pendingRemovals(visibleIDs: Set(visibleCandidates.map(\.id)))
    }

    private func removePending() {
        let visibleIDs = Set(visibleCandidates.map(\.id))
        Task {
            await scanner.removeSelected(visibleIDs: visibleIDs)
            store.refresh()
        }
    }

    // MARK: - Disk Gauge

    private var diskGauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Disk Space")
                    .font(.title3)
                    .bold()
                Spacer()
                Text(usageLabel)
                    .foregroundColor(gaugeColor)
                    .font(.title3)
                    .bold()
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh disk stats")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gaugeColor.opacity(0.8))
                        .frame(width: max(4, usedFraction * geo.size.width))
                }
            }
            .frame(height: 10)
            HStack {
                Text(formatBytes(store.totalBytes - store.availableBytes) + " used")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatBytes(store.availableBytes) + " free of " + formatBytes(store.totalBytes))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var usedFraction: Double {
        guard store.totalBytes > 0 else { return 0 }
        return Double(store.totalBytes - store.availableBytes) / Double(store.totalBytes)
    }

    private var usageLabel: String {
        String(format: "%.1f%% free", store.availablePercent)
    }

    private var gaugeColor: Color {
        if store.availablePercent < 5 { return .red }
        if store.availablePercent < 10 { return .orange }
        return .green
    }

    // MARK: - Cleanup Section

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cleanup Candidates")
                    .font(.headline)
                Spacer()
                Toggle("Hide < 1 GB", isOn: $hideSmall)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .font(.caption)
                if scanner.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Button("Scan Sizes") {
                        Task { await scanner.scanSizes() }
                    }
                    .disabled(scanner.isRemoving)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visibleCandidates) { candidate in
                        candidateRow(candidate)
                        Divider()
                    }
                }
            }
            HStack {
                Spacer()
                if scanner.isRemoving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                }
                Button("Remove Selected") {
                    showingConfirmation = true
                }
                .disabled(pendingRemovals.isEmpty || scanner.isRemoving || scanner.isScanning)
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: CleanupCandidate) -> some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { candidate.isSelected },
                    set: { _ in scanner.toggleSelection(id: candidate.id) }
                )
            )
            .labelsHidden()
            .disabled(scanner.isRemoving)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.body)
                Text(
                    copiedCandidateID == candidate.id
                        ? "Copied to clipboard"
                        : candidate.path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                sizeLabel(for: candidate)
                    .font(.caption)
                    .foregroundColor(candidate.sizeBytes.map(sizeColor) ?? .secondary)
                    .frame(width: 70, alignment: .trailing)
                if let date = candidate.lastModifiedDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            copyPath(of: candidate)
        }
        .help("Click to copy path")
    }

    private func copyPath(of candidate: CleanupCandidate) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(candidate.path.path, forType: .string)
        copiedCandidateID = candidate.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedCandidateID == candidate.id {
                copiedCandidateID = nil
            }
        }
    }

    @ViewBuilder
    private func sizeLabel(for candidate: CleanupCandidate) -> some View {
        if scanner.scanningCandidateIDs.contains(candidate.id), candidate.sizeBytes == nil {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 16, height: 16)
        } else if let size = candidate.sizeBytes {
            Text(formatBytes(size))
        } else {
            Text("—")
        }
    }

    private func sizeColor(_ bytes: Int64) -> Color {
        let gib: Int64 = 1_073_741_824
        if bytes >= 10 * gib { return .red }
        if bytes >= 3 * gib { return .orange }
        if bytes >= gib { return .yellow }
        return .secondary
    }

    private func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

// MARK: - Low Disk Banner

struct DiskLowBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Low disk space — click to view")
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.15))
        }
        .buttonStyle(.plain)
    }
}
