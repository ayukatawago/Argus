import ArgusConfigKit
import ArgusSupport
import Combine
import Foundation
import Monitors

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
                return ArgusConfig.intervalNanoseconds(seconds, default: 60)
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
        let usage = DiskUsage(total: total, free: free)
        let threshold = ArgusConfigStore.shared.config.diskMonitor.alertThresholdPercent
        totalBytes = usage.total
        availableBytes = usage.free
        availablePercent = usage.percentFree
        isLow = usage.isLow(threshold: threshold)
    }
}
