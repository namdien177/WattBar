import Foundation

@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot.loading
    @Published private(set) var topApps: [AppPowerUse] = []
    @Published private(set) var isScanningApps = false

    private var summaryTimer: Timer?
    private var detailTimer: Timer?
    private var detailTick = 0

    init() {
        refreshBattery()
        summaryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBattery()
            }
        }
        summaryTimer?.tolerance = 5
    }

    func beginDetailUpdates() {
        guard detailTimer == nil else { return }
        refreshBattery()
        refreshTopApps()

        detailTick = 0
        detailTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.detailTick += 1
                self.refreshBattery()
                if self.detailTick.isMultiple(of: 3) {
                    self.refreshTopApps()
                }
            }
        }
        detailTimer?.tolerance = 2
    }

    func endDetailUpdates() {
        detailTimer?.invalidate()
        detailTimer = nil
    }

    func refreshAll() {
        refreshBattery()
        refreshTopApps()
    }

    private func refreshBattery() {
        snapshot = PowerReader.read()
    }

    private func refreshTopApps() {
        guard !isScanningApps else { return }
        isScanningApps = true

        Task {
            let apps = await Task.detached(priority: .utility) {
                ProcessReader.topApps()
            }.value
            topApps = apps
            isScanningApps = false
        }
    }
}
