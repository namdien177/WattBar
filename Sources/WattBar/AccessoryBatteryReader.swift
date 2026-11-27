import Foundation
import IOKit.ps

/// Reads the battery level macOS keeps for connected accessories (the list `pmset -g accps` prints).
enum AccessoryBatteryReader {
    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    /// `kIOPSSourceAll` in IOKit's private header: every power source, accessories included.
    private static let allSources: Int32 = 0
    private static let accessoryType = "Accessory Source"

    static func read() -> [AccessoryBattery] {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        // IOKit always ships with macOS; without it there is nothing to read.
        guard let handle else { return [] }
        defer { dlclose(handle) }

        // The call is exported but not public; a future macOS may drop it, so the section just hides.
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return [] }
        let copyPowerSources = unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)

        // powerd had nothing to report.
        guard let information = copyPowerSources(allSources)?.takeRetainedValue() else { return [] }

        let sources = IOPSCopyPowerSourcesList(information).takeRetainedValue() as Array
        var descriptions: [[String: Any]] = []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            descriptions.append(description)
        }
        return makeAccessories(from: descriptions)
    }

    static func makeAccessories(from descriptions: [[String: Any]]) -> [AccessoryBattery] {
        var accessories: [AccessoryBattery] = []
        for description in descriptions {
            guard let accessory = accessory(from: description) else { continue }
            accessories.append(accessory)
        }
        return accessories.sorted(by: isListedBefore)
    }

    private static func accessory(from description: [String: Any]) -> AccessoryBattery? {
        // The Mac's own battery and UPS units are read elsewhere.
        guard description["Type"] as? String == accessoryType else { return nil }
        // Without a name there is nothing to label the ring with.
        guard let name = description["Name"] as? String, !name.isEmpty else { return nil }
        // Without both capacities there is no level to show.
        guard
            let currentCapacity = intValue(description["Current Capacity"]),
            let maximumCapacity = intValue(description["Max Capacity"]),
            maximumCapacity > 0
        else {
            return nil
        }

        let part = AccessoryPart(identifier: description["Part Identifier"] as? String)
        let deviceIdentifier = description["Accessory Identifier"] as? String ?? name
        let percentage = Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded())

        return AccessoryBattery(
            id: "\(deviceIdentifier)#\(part.rawValue)",
            deviceIdentifier: deviceIdentifier,
            name: name,
            category: description["Accessory Category"] as? String,
            part: part,
            percentage: min(max(percentage, 0), 100),
            isCharging: boolValue(description["Is Charging"]),
            lowWarnLevel: intValue(description["Low Warn Level"]) ?? 20,
            transport: description["Transport Type"] as? String
        )
    }

    private static func isListedBefore(_ first: AccessoryBattery, _ second: AccessoryBattery) -> Bool {
        // Parts of one device stay together, in L, R, Case order.
        if first.deviceIdentifier == second.deviceIdentifier {
            return first.part.sortOrder < second.part.sortOrder
        }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private static func boolValue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return number.boolValue
    }
}
