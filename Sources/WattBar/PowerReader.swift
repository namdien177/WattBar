import Foundation
import IOKit
import IOKit.ps

enum PowerReader {
    static func read(portMetadata: PortMetadata = .empty) -> PowerSnapshot {
        let registry = batteryRegistryProperties()
        let powerSource = powerSourceDescription()
        let adapter = adapterDescription()

        return makeSnapshot(
            registry: registry,
            powerSource: powerSource,
            adapter: adapter,
            portMetadata: portMetadata
        )
    }

    static func makeSnapshot(
        registry: [String: Any]?,
        powerSource: [String: Any]?,
        adapter: [String: Any]?,
        portMetadata: PortMetadata,
        measuredAt: Date = Date()
    ) -> PowerSnapshot {
        let telemetry = registry?["PowerTelemetryData"] as? [String: Any]

        let currentCapacity = intValue(powerSource?["Current Capacity"]) ?? 0
        let maximumCapacity = max(intValue(powerSource?["Max Capacity"]) ?? 100, 1)
        let percentage = min(max(Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded()), 0), 100)

        let isConnected = boolValue(registry?["ExternalConnected"]) || powerSource?["Power Source State"] as? String == "AC Power"

        let voltageMillivolts = doubleValue(registry?["Voltage"])
        let currentMilliamps = doubleValue(registry?["InstantAmperage"])
            ?? doubleValue(registry?["Amperage"])

        let fallbackBatteryPower = calculateBatteryPower(
            voltageMillivolts: voltageMillivolts,
            currentMilliamps: currentMilliamps
        )
        let telemetryBatteryPower = doubleValue(telemetry?["BatteryPower"]).map { $0 / 1_000 }
        let batteryPowerWatts = telemetryBatteryPower ?? fallbackBatteryPower

        let sourceCharging = boolValue(powerSource?["Is Charging"])
        let isCharging: Bool
        if let batteryPowerWatts {
            isCharging = batteryPowerWatts > 0.1
        } else {
            isCharging = boolValue(registry?["IsCharging"]) || sourceCharging
        }

        let externalDevices = externalPowerDevices(
            registry: registry,
            namesByPort: portMetadata.deviceNamesByPort
        )
        let externalPowerWatts = externalDevices.reduce(0) { $0 + $1.watts }
        let systemLoadWatts = doubleValue(telemetry?["SystemLoad"]).map { $0 / 1_000 }
        let macPowerWatts = systemLoadWatts.map { max($0 - externalPowerWatts, 0) }
        let inputWatts = doubleValue(telemetry?["SystemPowerIn"]).map { $0 / 1_000 }

        // Each estimate only means something in its own power state.
        var minutesToFull: Int?
        if isCharging {
            minutesToFull = positiveMinutes(intValue(powerSource?["Time to Full Charge"]))
        }
        var minutesToEmpty: Int?
        if !isConnected {
            minutesToEmpty = positiveMinutes(intValue(powerSource?["Time to Empty"]))
        }
        let isFullyCharged = boolValue(powerSource?["Is Charged"]) || boolValue(registry?["FullyCharged"])
        let adapterWatts = intValue(adapter?["Watts"])

        return PowerSnapshot(
            percentage: percentage,
            isCharging: isCharging,
            isConnected: isConnected,
            batteryPowerWatts: batteryPowerWatts,
            inputWatts: inputWatts,
            macPowerWatts: macPowerWatts,
            externalDevices: externalDevices,
            hasDetailedPowerTelemetry: telemetry != nil,
            minutesToFull: minutesToFull,
            minutesToEmpty: minutesToEmpty,
            isFullyCharged: isFullyCharged,
            powerSource: sourceName(
                isConnected: isConnected,
                adapter: adapter,
                adapterWatts: adapterWatts,
                inputPortName: portMetadata.inputPortName
            ),
            adapterRatingWatts: adapterWatts,
            cycleCount: intValue(registry?["CycleCount"]),
            measuredAt: measuredAt
        )
    }

    static func calculateBatteryPower(
        voltageMillivolts: Double?,
        currentMilliamps: Double?
    ) -> Double? {
        guard
            let voltageMillivolts,
            let currentMilliamps,
            voltageMillivolts > 0
        else {
            return nil
        }
        return voltageMillivolts * currentMilliamps / 1_000_000
    }

    private static func positiveMinutes(_ minutes: Int?) -> Int? {
        // macOS reports -1 (or 0) while it is still calculating.
        guard let minutes, minutes > 0 else { return nil }
        return minutes
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
        adapterWatts: Int?,
        inputPortName: String?
    ) -> String {
        guard isConnected else { return "Internal battery" }

        let rawDescription = (adapter?["Description"] as? String)?.lowercased() ?? ""
        let description: String
        if let inputPortName {
            description = inputPortName
        } else if rawDescription.contains("pd charger") {
            description = "USB-C PD charger"
        } else if rawDescription.isEmpty {
            description = "External power"
        } else {
            description = rawDescription.capitalized
        }

        guard let adapterWatts else { return description }
        return "\(adapterWatts) W \(description)"
    }

    private static func externalPowerDevices(
        registry: [String: Any]?,
        namesByPort: [Int: String]
    ) -> [ExternalPowerDevice] {
        guard let powerOutputs = registry?["PowerOutDetails"] as? [[String: Any]] else {
            return []
        }

        return powerOutputs.compactMap { output in
            guard
                let portNumber = intValue(output["PortIndex"]),
                let milliwatts = doubleValue(output["Watts"]),
                milliwatts > 50
            else {
                return nil
            }

            let name = namesByPort[portNumber] ?? "Powered device"
            return ExternalPowerDevice(
                portNumber: portNumber,
                name: name,
                watts: milliwatts / 1_000
            )
        }
        .sorted { $0.portNumber < $1.portNumber }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text)
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return number.boolValue
    }
}
