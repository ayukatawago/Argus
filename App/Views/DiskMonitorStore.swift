import ArgusConfigKit
import ArgusSupport
import Combine
import Foundation

@MainActor
final class DiskMonitorStore: ObservableObject {
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var availableBytes: Int64 = 0
    @Published private(set) var availablePercent: Double = 100
    @Published private(set) var isLow: Bool = false

    private var monitorTask: Task<Void, Never>?

    func start() {
        guard monitorTask == nil else { return }
        refresh()
        monitorTask = PollingTask.repeating(
            order: .sleepThenAct,
            interval: {
                let seconds = await ArgusConfigStore.shared.config.diskMonitor.checkIntervalSeconds
                return UInt64(seconds * 1_000_000_000)
            },
            action: { [weak self] in await self?.refresh() }
        )
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refresh() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        else { return }
        let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let percent = total > 0 ? Double(free) / Double(total) * 100 : 100
        let threshold = ArgusConfigStore.shared.config.diskMonitor.alertThresholdPercent
        let wasLow = isLow
        totalBytes = total
        availableBytes = free
        availablePercent = percent
        isLow = percent < threshold
        if isLow && !wasLow {
            NotificationCenter.default.post(name: .diskSpaceLow, object: nil)
        }
    }
}
