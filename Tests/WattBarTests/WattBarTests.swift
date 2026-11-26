import XCTest
@testable import WattBar

final class WattBarTests: XCTestCase {
    func testBatteryPowerCalculation() {
        let watts = PowerReader.calculateBatteryPower(
            voltageMillivolts: 11_757,
            currentMilliamps: 1_983
        )
        XCTAssertEqual(watts ?? 0, 23.314_131, accuracy: 0.000_001)
    }

    func testBatteryPowerPreservesDischargeDirection() {
        let watts = PowerReader.calculateBatteryPower(
            voltageMillivolts: 11_500,
            currentMilliamps: -1_800
        )
        XCTAssertEqual(watts ?? 0, -20.7, accuracy: 0.000_001)
    }

    func testDetailedTelemetryBuildsMeasuredPowerBalance() {
        let snapshot = PowerReader.makeSnapshot(
            registry: [
                "ExternalConnected": true,
                "IsCharging": true,
                "Voltage": 12_731,
                "InstantAmperage": -1_837,
                "CycleCount": 124,
                "PowerTelemetryData": [
                    "SystemPowerIn": 42_604,
                    "BatteryPower": "-15618",
                    "SystemLoad": 58_222
                ],
                "PowerOutDetails": [
                    ["PortIndex": 1, "Watts": 1_870],
                    ["PortIndex": 2, "Watts": 14_882]
                ]
            ],
            powerSource: [
                "Current Capacity": 95,
                "Max Capacity": 100,
                "Is Charging": true,
                "Power Source State": "AC Power",
                "Time to Full Charge": 30
            ],
            adapter: ["Watts": 45, "Description": "pd charger"],
            portMetadata: PortMetadata(
                inputPortName: "MagSafe 3",
                deviceNamesByPort: [1: "Newdox", 2: "iPad"]
            )
        )

        XCTAssertFalse(snapshot.isCharging)
        XCTAssertTrue(snapshot.isBatteryAssisting)
        XCTAssertNil(snapshot.minutesToFull)
        XCTAssertEqual(snapshot.inputWatts ?? 0, 42.604, accuracy: 0.001)
        XCTAssertEqual(snapshot.batteryPowerWatts ?? 0, -15.618, accuracy: 0.001)
        XCTAssertEqual(snapshot.externalPowerWatts, 16.752, accuracy: 0.001)
        XCTAssertEqual(snapshot.macPowerWatts ?? 0, 41.470, accuracy: 0.001)
        XCTAssertEqual(snapshot.powerSource, "45 W MagSafe 3")
        XCTAssertEqual(snapshot.externalDevices.map(\.name), ["Newdox", "iPad"])
    }

    func testPositiveBatteryPowerMeansCharging() {
        let snapshot = PowerReader.makeSnapshot(
            registry: [
                "ExternalConnected": true,
                "PowerTelemetryData": ["BatteryPower": 12_000]
            ],
            powerSource: [
                "Current Capacity": 60,
                "Max Capacity": 100,
                "Power Source State": "AC Power",
                "Time to Full Charge": 90
            ],
            adapter: nil,
            portMetadata: .empty
        )

        XCTAssertTrue(snapshot.isCharging)
        XCTAssertEqual(snapshot.chargingWatts, 12)
        XCTAssertEqual(snapshot.minutesToFull, 90)
    }

    func testDurationFormatting() {
        XCTAssertEqual(PowerFormatting.duration(minutes: 169), "2h 49m")
        XCTAssertEqual(PowerFormatting.duration(minutes: nil), "Estimating…")
    }

    func testProcessOutputGroupsHelperProcessesByApp() {
        let output = """
          101 12.5 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          102  4.0 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
          103  8.2 /Applications/Slack.app/Contents/MacOS/Slack
          104 90.0 /usr/libexec/some-system-process
        """

        XCTAssertEqual(ProcessReader.parse(output), [
            AppPowerUse(name: "Google Chrome", cpuPercent: 16.5),
            AppPowerUse(name: "Slack", cpuPercent: 8.2)
        ])
    }

    func testFullBatteryShowsFullSymbolEvenWhenAssisting() {
        let snapshot = makeSnapshot(percentage: 100, isConnected: true, batteryPowerWatts: -24.6)

        XCTAssertTrue(snapshot.isBatteryAssisting)
        XCTAssertEqual(snapshot.menuBarSymbol, "battery.100percent")
    }

    func testBatterySymbolFollowsLevel() {
        let symbols = [100, 80, 50, 20, 5].map { makeSnapshot(percentage: $0).menuBarSymbol }

        XCTAssertEqual(symbols, [
            "battery.100percent",
            "battery.75percent",
            "battery.50percent",
            "battery.25percent",
            "battery.0percent"
        ])
    }

    func testChargingShowsBoltSymbol() {
        let snapshot = makeSnapshot(percentage: 40, isConnected: true, batteryPowerWatts: 30)

        XCTAssertEqual(snapshot.menuBarSymbol, "battery.100percent.bolt")
    }

    func testTimeToEmptyIsReadOnlyOnBattery() {
        let onBattery = PowerReader.makeSnapshot(
            registry: [:],
            powerSource: ["Current Capacity": 70, "Max Capacity": 100, "Time to Empty": 310],
            adapter: nil,
            portMetadata: .empty
        )
        let calculating = PowerReader.makeSnapshot(
            registry: [:],
            powerSource: ["Current Capacity": 70, "Max Capacity": 100, "Time to Empty": -1],
            adapter: nil,
            portMetadata: .empty
        )

        XCTAssertEqual(onBattery.minutesToEmpty, 310)
        XCTAssertNil(calculating.minutesToEmpty)
    }

    func testFullyChargedComesFromPowerSourceOrRegistry() {
        let fromPowerSource = PowerReader.makeSnapshot(
            registry: ["ExternalConnected": true],
            powerSource: ["Current Capacity": 100, "Max Capacity": 100, "Is Charged": true],
            adapter: nil,
            portMetadata: .empty
        )
        let fromRegistry = PowerReader.makeSnapshot(
            registry: ["ExternalConnected": true, "FullyCharged": true],
            powerSource: ["Current Capacity": 100, "Max Capacity": 100],
            adapter: nil,
            portMetadata: .empty
        )

        XCTAssertTrue(fromPowerSource.isFullyCharged)
        XCTAssertTrue(fromRegistry.isFullyCharged)
    }

    func testDetectsPlugUnplugAndFull() {
        let onBattery = makeSnapshot(percentage: 60)
        let plugged = makeSnapshot(percentage: 60, isConnected: true, batteryPowerWatts: 30)
        let full = makeSnapshot(percentage: 100, isConnected: true, isFullyCharged: true)

        XCTAssertEqual(PowerEventDetector.event(from: onBattery, to: plugged), .pluggedIn)
        XCTAssertEqual(PowerEventDetector.event(from: plugged, to: onBattery), .unplugged)
        XCTAssertEqual(PowerEventDetector.event(from: plugged, to: full), .fullyCharged)
        XCTAssertNil(PowerEventDetector.event(from: full, to: full))
        XCTAssertNil(PowerEventDetector.event(from: onBattery, to: onBattery))
    }

    func testPluggedInNotificationWaitsForTimeToFull() {
        let estimating = makeSnapshot(percentage: 64, isConnected: true, batteryPowerWatts: 30)
        let estimated = makeSnapshot(percentage: 64, isConnected: true, batteryPowerWatts: 30, minutesToFull: 80)

        XCTAssertFalse(PowerNotificationText.hasEstimate(for: .pluggedIn, snapshot: estimating))
        XCTAssertTrue(PowerNotificationText.hasEstimate(for: .pluggedIn, snapshot: estimated))
        XCTAssertEqual(
            PowerNotificationText.content(for: .pluggedIn, snapshot: estimated),
            PowerNotificationContent(title: "Plugged in", body: "64% · Full in 1h 20m")
        )
        XCTAssertEqual(
            PowerNotificationText.content(for: .pluggedIn, snapshot: estimating).body,
            "64% · Estimating time to full"
        )
    }

    func testUnpluggedNotificationShowsTimeLeft() {
        let snapshot = makeSnapshot(percentage: 82, minutesToEmpty: 310)

        XCTAssertEqual(
            PowerNotificationText.content(for: .unplugged, snapshot: snapshot),
            PowerNotificationContent(title: "On battery", body: "82% · About 5h 10m left")
        )
    }

    func testFullyChargedNotificationNamesTheSource() {
        let snapshot = makeSnapshot(percentage: 100, isConnected: true, isFullyCharged: true)

        XCTAssertEqual(
            PowerNotificationText.content(for: .fullyCharged, snapshot: snapshot),
            PowerNotificationContent(title: "Fully charged", body: "100% · on 100 W USB-C")
        )
    }

    private func makeSnapshot(
        percentage: Int,
        isConnected: Bool = false,
        batteryPowerWatts: Double? = nil,
        minutesToFull: Int? = nil,
        minutesToEmpty: Int? = nil,
        isFullyCharged: Bool = false
    ) -> PowerSnapshot {
        PowerSnapshot(
            percentage: percentage,
            isCharging: (batteryPowerWatts ?? 0) > 0.1,
            isConnected: isConnected,
            batteryPowerWatts: batteryPowerWatts,
            inputWatts: nil,
            macPowerWatts: nil,
            externalDevices: [],
            hasDetailedPowerTelemetry: true,
            minutesToFull: minutesToFull,
            minutesToEmpty: minutesToEmpty,
            isFullyCharged: isFullyCharged,
            powerSource: "100 W USB-C",
            adapterRatingWatts: 100,
            cycleCount: 138,
            measuredAt: Date()
        )
    }
}
