import XCTest
@testable import WattBar

final class WattBarTests: XCTestCase {
    func testChargingWattCalculation() {
        let watts = PowerReader.calculateChargingWatts(
            isCharging: true,
            voltageMillivolts: 11_757,
            currentMilliamps: 1_983
        )
        XCTAssertEqual(watts ?? 0, 23.314_131, accuracy: 0.000_001)
    }

    func testNoWattValueWhenNotCharging() {
        XCTAssertNil(PowerReader.calculateChargingWatts(
            isCharging: false,
            voltageMillivolts: 11_500,
            currentMilliamps: -1_800
        ))
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
