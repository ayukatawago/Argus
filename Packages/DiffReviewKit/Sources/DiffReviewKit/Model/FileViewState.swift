import Foundation

/// Per-file Viewed and collapsed state for the all-files list, kept in memory only. Pure so the
/// reconcile rules can be tested against plain `DiffFile` values.
struct FileViewState: Equatable {
    /// Files over this many changed lines start collapsed on first sight, like GitHub's "Load diff".
    static let autoCollapseLineThreshold = 500

    /// Path → content signature at the moment the file was marked Viewed.
    var viewedFiles: [String: Int] = [:]
    var collapsedFilePaths: Set<String> = []
    /// Every path that has appeared in a diff this session, so auto-collapse only fires once per path.
    var seenFilePaths: Set<String> = []

    /// Marking a file Viewed collapses it; un-marking it expands it again.
    mutating func toggleViewed(_ file: DiffFile) {
        if viewedFiles[file.path] != nil {
            viewedFiles[file.path] = nil
            collapsedFilePaths.remove(file.path)
        } else {
            viewedFiles[file.path] = file.contentSignature
            collapsedFilePaths.insert(file.path)
        }
    }

    /// Brings the state in line with a freshly parsed diff:
    /// - A Viewed file whose content is unchanged stays Viewed. Its collapse state is kept as it is, so
    ///   a file the reviewer re-expanded stays expanded.
    /// - A Viewed file whose content changed is un-viewed and expanded, as GitHub does.
    /// - An unviewed file keeps whatever collapse state the reviewer gave it, except that a file over
    ///   the line threshold is auto-collapsed the first time it appears.
    /// - Files no longer in the diff are pruned.
    mutating func reconcile(with files: [DiffFile]) {
        var viewed: [String: Int] = [:]
        var collapsed: Set<String> = []
        for file in files {
            let path = file.path
            let signature = file.contentSignature
            if viewedFiles[path] == signature {
                viewed[path] = signature
                if collapsedFilePaths.contains(path) { collapsed.insert(path) }
            } else if viewedFiles[path] == nil {
                if seenFilePaths.contains(path) {
                    if collapsedFilePaths.contains(path) { collapsed.insert(path) }
                } else if changedLineCount(of: file) > Self.autoCollapseLineThreshold {
                    collapsed.insert(path)
                }
            }
        }
        viewedFiles = viewed
        collapsedFilePaths = collapsed
        seenFilePaths.formUnion(files.map(\.path))
    }

    private func changedLineCount(of file: DiffFile) -> Int {
        file.additionCount + file.deletionCount
    }
}
