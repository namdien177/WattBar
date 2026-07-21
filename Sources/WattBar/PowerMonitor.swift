import Foundation

@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot.loading
    @Published private(set) var topApps: [AppPowerUse] = []
    @Published private(set) var isScanningApps = false

    private var summaryTimer: Timer?
    private var detailTimer: Timer?
    private var detailTick = 0
    private var portMetadata = PortMetadata.empty
    private var isScanningPorts = false

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
        refreshPortMetadata()
        refreshTopApps()

        detailTick = 0
        detailTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.detailTick += 1
                self.refreshBattery()
                if self.detailTick.isMultiple(of: 3) {
                    self.refreshPortMetadata()
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
        refreshPortMetadata()
        refreshTopApps()
    }

    private func refreshBattery() {
        snapshot = PowerReader.read(portMetadata: portMetadata)
    }

    private func refreshPortMetadata() {
        guard !isScanningPorts else { return }
        isScanningPorts = true

        Task {
            let metadata = await Task.detached(priority: .utility) {
                ExternalDeviceReader.read()
            }.value
            portMetadata = metadata
            isScanningPorts = false
            refreshBattery()
        }
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
