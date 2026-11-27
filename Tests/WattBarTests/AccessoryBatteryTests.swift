import XCTest
@testable import WattBar

final class AccessoryBatteryTests: XCTestCase {
    // Shapes copied from `IOPSCopyPowerSourcesByType` on a Mac15,7 with macOS 27.2.1.
    private let keychron: [String: Any] = [
        "Type": "Accessory Source",
        "Name": "Keychron M6",
        "Accessory Category": "Mouse",
        "Accessory Identifier": "4E7989CD",
        "Current Capacity": 96,
        "Max Capacity": 100,
        "Low Warn Level": 20,
        "Transport Type": "Bluetooth LE"
    ]
    private let glove80: [String: Any] = [
        "Type": "Accessory Source",
        "Name": "Glove80",
        "Accessory Identifier": "25BBF3D5",
        "Current Capacity": 100,
        "Max Capacity": 100,
        "Low Warn Level": 20,
        "Transport Type": "Bluetooth LE"
    ]
    private let internalBattery: [String: Any] = [
        "Type": "InternalBattery",
        "Name": "InternalBattery-0",
        "Current Capacity": 80,
        "Max Capacity": 100
    ]

    func testReadsAccessoriesAndSkipsTheMacBattery() {
        let accessories = AccessoryBatteryReader.makeAccessories(from: [internalBattery, keychron, glove80])

        XCTAssertEqual(accessories.map(\.name), ["Glove80", "Keychron M6"])
        XCTAssertEqual(accessories.map(\.percentage), [100, 96])
        XCTAssertEqual(accessories[1].symbol, "computermouse")
        XCTAssertTrue(accessories[1].isBluetooth)
    }

    func testMissingCategoryFallsBackToGenericSymbol() {
        let accessories = AccessoryBatteryReader.makeAccessories(from: [glove80])

        XCTAssertEqual(accessories.first?.symbol, "dot.radiowaves.left.and.right")
    }

    func testLowIsAtOrBelowTheWarnLevel() {
        let atLevel = accessory(percentage: 20)
        let aboveLevel = accessory(percentage: 21)

        XCTAssertTrue(atLevel.isLow)
        XCTAssertFalse(aboveLevel.isLow)
    }

    func testChargingFlagIsRead() {
        var headset = keychron
        headset["Name"] = "Scallop"
        headset["Accessory Category"] = "Headset"
        headset["Is Charging"] = true

        let accessories = AccessoryBatteryReader.makeAccessories(from: [headset])

        XCTAssertEqual(accessories.first?.isCharging, true)
        XCTAssertEqual(accessories.first?.symbol, "headphones")
    }

    func testAirPodsPartsStayTogetherInOrder() {
        let parts = ["Case", "Right", "Left"].map { part -> [String: Any] in
            [
                "Type": "Accessory Source",
                "Name": "AirPods Pro",
                "Accessory Identifier": "AIRPODS",
                "Part Identifier": part,
                "Current Capacity": 50,
                "Max Capacity": 100
            ]
        }

        let accessories = AccessoryBatteryReader.makeAccessories(from: parts)

        XCTAssertEqual(accessories.map(\.displayName), ["AirPods Pro L", "AirPods Pro R", "AirPods Pro Case"])
        XCTAssertEqual(Set(accessories.map(\.id)).count, 3)
        XCTAssertEqual(Set(accessories.map(\.deviceIdentifier)), ["AIRPODS"])
    }

    func testSkipsEntriesWithoutUsableCapacity() {
        var zeroMaximum = keychron
        zeroMaximum["Max Capacity"] = 0
        var missingCurrent = glove80
        missingCurrent.removeValue(forKey: "Current Capacity")

        XCTAssertTrue(AccessoryBatteryReader.makeAccessories(from: [zeroMaximum, missingCurrent]).isEmpty)
        XCTAssertTrue(AccessoryBatteryReader.makeAccessories(from: []).isEmpty)
    }

    func testLowBatteryIsAnnouncedOncePerDischarge() {
        let low = accessory(percentage: 18)
        let lower = accessory(percentage: 12)
        let charging = accessory(percentage: 12, isCharging: true)
        let recovered = accessory(percentage: 60)

        let first = AccessoryLowBatteryDetector.check([low], announcedIDs: [])
        XCTAssertEqual(first.toAnnounce, [low])

        let second = AccessoryLowBatteryDetector.check([lower], announcedIDs: first.announcedIDs)
        XCTAssertTrue(second.toAnnounce.isEmpty)

        let afterCharge = AccessoryLowBatteryDetector.check([charging], announcedIDs: second.announcedIDs)
        XCTAssertTrue(afterCharge.toAnnounce.isEmpty)
        XCTAssertEqual(
            AccessoryLowBatteryDetector.check([lower], announcedIDs: afterCharge.announcedIDs).toAnnounce,
            [lower]
        )

        let afterRecovery = AccessoryLowBatteryDetector.check([recovered], announcedIDs: second.announcedIDs)
        XCTAssertTrue(afterRecovery.announcedIDs.isEmpty)
    }

    func testDisconnectedLowDeviceStaysQuietOnReconnect() {
        let low = accessory(percentage: 15)

        let announced = AccessoryLowBatteryDetector.check([low], announcedIDs: [])
        let gone = AccessoryLowBatteryDetector.check([], announcedIDs: announced.announcedIDs)
        let back = AccessoryLowBatteryDetector.check([low], announcedIDs: gone.announcedIDs)

        XCTAssertTrue(back.toAnnounce.isEmpty)
    }

    func testLowBatteryNotificationText() {
        XCTAssertEqual(
            AccessoryLowBatteryDetector.content(for: accessory(percentage: 18)),
            PowerNotificationContent(title: "Keychron M6 battery low", body: "18% left")
        )
    }

    func testPowerConsumersFollowTheMeasuredBalance() {
        let snapshot = PowerReader.makeSnapshot(
            registry: [
                "ExternalConnected": true,
                "PowerTelemetryData": ["SystemPowerIn": 60_000, "BatteryPower": 10_000, "SystemLoad": 50_000],
                "PowerOutDetails": [["PortIndex": 2, "Watts": 15_000]]
            ],
            powerSource: ["Current Capacity": 50, "Max Capacity": 100],
            adapter: nil,
            portMetadata: PortMetadata(inputPortName: "MagSafe 3", deviceNamesByPort: [2: "iPad"])
        )

        XCTAssertEqual(snapshot.powerConsumers.map(\.id), ["mac", "battery", "device-2"])
        XCTAssertEqual(snapshot.powerConsumers.map(\.watts), [35, 10, 15])
        XCTAssertEqual(snapshot.powerSourceSummary, "60.0 W in")
    }

    func testOnBatteryTheSummaryNamesTheBattery() {
        let snapshot = PowerReader.makeSnapshot(
            registry: ["PowerTelemetryData": ["BatteryPower": -12_500, "SystemLoad": 12_500]],
            powerSource: ["Current Capacity": 50, "Max Capacity": 100],
            adapter: nil,
            portMetadata: .empty
        )

        XCTAssertEqual(snapshot.powerSourceSummary, "12.5 W from battery")
        XCTAssertEqual(snapshot.powerConsumers.map(\.id), ["mac"])
    }

    private func accessory(percentage: Int, isCharging: Bool = false) -> AccessoryBattery {
        AccessoryBattery(
            id: "4E7989CD#whole",
            deviceIdentifier: "4E7989CD",
            name: "Keychron M6",
            category: "Mouse",
            part: .whole,
            percentage: percentage,
            isCharging: isCharging,
            lowWarnLevel: 20,
            transport: "Bluetooth LE"
        )
    }
}
