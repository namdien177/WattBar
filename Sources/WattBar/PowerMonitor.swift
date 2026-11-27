import Foundation
import IOKit.ps

@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot.loading
    @Published private(set) var topApps: [AppPowerUse] = []
    @Published private(set) var isScanningApps = false
    @Published private(set) var accessories: [AccessoryBattery] = []
    /// Keyed by `AccessoryBattery.deviceIdentifier`.
    @Published private(set) var disconnectStates: [String: AccessoryDisconnectState] = [:]

    private var summaryTimer: Timer?
    private var detailTimer: Timer?
    private var detailTick = 0
    private var portMetadata = PortMetadata.empty
    private var isScanningPorts = false
    private var isReadingAccessories = false
    private let notifier = PowerNotifier()
    private var powerSourceRunLoopSource: CFRunLoopSource?

    /// How long to wait for macOS to drop a disconnected device before calling it a failure.
    private static let disconnectChecks = 5
    private static let failureMessageSeconds = 3

    init() {
        refreshBattery()
        refreshAccessories()
        startPowerSourceNotifications()
        // Accessories are read here too, so low-battery alerts arrive while the popover is closed.
        summaryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBattery()
                self?.refreshAccessories()
            }
        }
        summaryTimer?.tolerance = 5
    }

    func beginDetailUpdates() {
        guard detailTimer == nil else { return }
        refreshBattery()
        refreshAccessories()
        refreshPortMetadata()
        refreshTopApps()

        detailTick = 0
        detailTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.detailTick += 1
                self.refreshBattery()
                self.refreshAccessories()
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
        refreshAccessories()
        refreshPortMetadata()
        refreshTopApps()
    }

    func disconnect(_ accessory: AccessoryBattery) {
        let deviceIdentifier = accessory.deviceIdentifier
        // Already disconnecting this device.
        guard disconnectStates[deviceIdentifier] != .inProgress else { return }
        disconnectStates[deviceIdentifier] = .inProgress

        let name = accessory.name
        Task {
            let isDisconnected = await Task.detached(priority: .userInitiated) {
                BluetoothDisconnector.disconnect(deviceNamed: name)
            }.value
            await finishDisconnect(deviceIdentifier, isDisconnected: isDisconnected)
        }
    }

    private func finishDisconnect(_ deviceIdentifier: String, isDisconnected: Bool) async {
        // macOS refused, or no single connected Bluetooth device has this name.
        guard isDisconnected else {
            await showDisconnectFailure(deviceIdentifier)
            return
        }

        // macOS drops the device from its power sources a moment after the link closes.
        for _ in 0..<Self.disconnectChecks {
            try? await Task.sleep(for: .seconds(1))
            await readAccessories()
            if !isListed(deviceIdentifier) {
                disconnectStates[deviceIdentifier] = nil
                return
            }
        }
        await showDisconnectFailure(deviceIdentifier)
    }

    private func showDisconnectFailure(_ deviceIdentifier: String) async {
        disconnectStates[deviceIdentifier] = .failed
        try? await Task.sleep(for: .seconds(Self.failureMessageSeconds))
        // A newer attempt started while the message was showing.
        guard disconnectStates[deviceIdentifier] == .failed else { return }
        disconnectStates[deviceIdentifier] = nil
    }

    private func isListed(_ deviceIdentifier: String) -> Bool {
        accessories.contains { $0.deviceIdentifier == deviceIdentifier }
    }

    private func refreshBattery() {
        snapshot = PowerReader.read(portMetadata: portMetadata)
        notifier.observe(snapshot)
    }

    private func refreshAccessories() {
        Task {
            await readAccessories()
        }
    }

    private func readAccessories() async {
        // One read at a time; the next timer tick catches up.
        guard !isReadingAccessories else { return }
        isReadingAccessories = true

        let current = await Task.detached(priority: .utility) {
            AccessoryBatteryReader.read()
        }.value
        accessories = current
        isReadingAccessories = false
        notifier.observeAccessories(current)
    }

    /// macOS calls back on plug, unplug and level changes, so events show up immediately.
    private func startPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.refreshBattery()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
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
