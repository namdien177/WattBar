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
}
