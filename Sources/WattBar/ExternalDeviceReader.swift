import Foundation
import IOKit

struct PortMetadata: Sendable, Equatable {
    let inputPortName: String?
    let deviceNamesByPort: [Int: String]

    static let empty = PortMetadata(inputPortName: nil, deviceNamesByPort: [:])
}

enum ExternalDeviceReader {
    static func read() -> PortMetadata {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return .empty }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        let result = IORegistryEntryCreateIterator(
            root,
            "IOPort",
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )
        guard result == KERN_SUCCESS, iterator != 0 else { return .empty }
        defer { IOObjectRelease(iterator) }

        var inputPortName: String?
        var namesByPort: [Int: String] = [:]

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            guard let properties = properties(for: entry) else { continue }

            if properties["WinningPowerSourceOption"] != nil {
                inputPortName = properties["ParentBuiltInPortTypeDescription"] as? String
                    ?? properties["ParentPortTypeDescription"] as? String
            }

            guard
                properties["ParentBuiltInPortTypeDescription"] as? String == "USB-C",
                let portNumber = intValue(properties["ParentBuiltInPortNumber"])
                    ?? intValue(properties["ParentPortNumber"]),
                let product = productName(from: properties)
            else {
                continue
            }

            namesByPort[portNumber] = namesByPort[portNumber] ?? product
        }

        return PortMetadata(
            inputPortName: inputPortName,
            deviceNamesByPort: namesByPort
        )
    }

    private static func properties(for entry: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS else { return nil }
        return unmanagedProperties?.takeRetainedValue() as? [String: Any]
    }

    private static func productName(from properties: [String: Any]) -> String? {
        let keys = ["Product", "ProductName", "USB Product Name"]
        for key in keys {
            if let name = properties[key] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return number.intValue
    }
}
