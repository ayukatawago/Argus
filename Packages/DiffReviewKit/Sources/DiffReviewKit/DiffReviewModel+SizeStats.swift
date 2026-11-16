import Foundation

extension DiffReviewModel {
    /// Total/production/test breakdown of the current diff, in that order.
    public var sizeStats: [DiffSizeStat] {
        let testFiles = files.filter { DiffFileClassifier.isTestFile($0.path) }
        let productionFiles = files.filter { !DiffFileClassifier.isTestFile($0.path) }
        return [
            DiffSizeStat(label: "Total", files: files),
            DiffSizeStat(label: "Production", files: productionFiles),
            DiffSizeStat(label: "Test", files: testFiles),
        ]
    }
}
