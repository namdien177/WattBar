import Foundation
import IOKit
import IOKit.ps

enum PowerReader {
    static func read() -> PowerSnapshot {
        let registry = batteryRegistryProperties()
        let powerSource = powerSourceDescription()
        let adapter = adapterDescription()

        let currentCapacity = intValue(powerSource?["Current Capacity"]) ?? 0
        let maximumCapacity = max(intValue(powerSource?["Max Capacity"]) ?? 100, 1)
        let percentage = min(max(Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded()), 0), 100)

        let registryCharging = boolValue(registry?["IsCharging"])
        let sourceCharging = boolValue(powerSource?["Is Charging"])
        let isCharging = registryCharging || sourceCharging
        let isConnected = boolValue(registry?["ExternalConnected"]) || powerSource?["Power Source State"] as? String == "AC Power"

        let voltageMillivolts = doubleValue(registry?["Voltage"])
        let currentMilliamps = doubleValue(registry?["InstantAmperage"])
            ?? doubleValue(registry?["Amperage"])
        let chargingWatts = calculateChargingWatts(
            isCharging: isCharging,
            voltageMillivolts: voltageMillivolts,
            currentMilliamps: currentMilliamps
        )

        let rawMinutes = intValue(powerSource?["Time to Full Charge"])
        let minutesToFull = isCharging && (rawMinutes ?? 0) > 0 ? rawMinutes : nil
        let adapterWatts = intValue(adapter?["Watts"])

        return PowerSnapshot(
            percentage: percentage,
            isCharging: isCharging,
            isConnected: isConnected,
            chargingWatts: chargingWatts,
            minutesToFull: minutesToFull,
            powerSource: sourceName(isConnected: isConnected, adapter: adapter, adapterWatts: adapterWatts),
            adapterRatingWatts: adapterWatts,
            cycleCount: intValue(registry?["CycleCount"]),
            measuredAt: Date()
        )
    }

    static func calculateChargingWatts(
        isCharging: Bool,
        voltageMillivolts: Double?,
        currentMilliamps: Double?
    ) -> Double? {
        guard
            isCharging,
            let voltageMillivolts,
            let currentMilliamps,
            voltageMillivolts > 0,
            currentMilliamps > 0
        else {
            return nil
        }
        return voltageMillivolts * currentMilliamps / 1_000_000
    }

    private static func batteryRegistryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS else { return nil }
        return unmanagedProperties?.takeRetainedValue() as? [String: Any]
    }

    private static func powerSourceDescription() -> [String: Any]? {
        let information = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(information).takeRetainedValue() as Array

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery"
            else {
                continue
            }
            return description
        }
        return nil
    }

    private static func adapterDescription() -> [String: Any]? {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
    }

    private static func sourceName(
        isConnected: Bool,
        adapter: [String: Any]?,
        adapterWatts: Int?
    ) -> String {
        guard isConnected else { return "Internal battery" }

        let rawDescription = (adapter?["Description"] as? String)?.lowercased() ?? ""
        let description: String
        if rawDescription.contains("pd charger") {
            description = "USB-C PD charger"
        } else if rawDescription.isEmpty {
            description = "External power"
        } else {
            description = rawDescription.capitalized
        }

        guard let adapterWatts else { return description }
        return "\(adapterWatts) W \(description)"
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }

    private static func boolValue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return number.boolValue
    }
}
