import Foundation

/// One battery inside a wireless accessory. AirPods report each bud and the case as separate parts.
enum AccessoryPart: String, Sendable, Equatable {
    case whole
    case left
    case right
    case chargingCase

    init(identifier: String?) {
        switch identifier {
        case "Left":
            self = .left
        case "Right":
            self = .right
        case "Case":
            self = .chargingCase
        default:
            self = .whole
        }
    }

    var label: String? {
        switch self {
        case .whole:
            return nil
        case .left:
            return "L"
        case .right:
            return "R"
        case .chargingCase:
            return "Case"
        }
    }

    var sortOrder: Int {
        switch self {
        case .whole:
            return 0
        case .left:
            return 1
        case .right:
            return 2
        case .chargingCase:
            return 3
        }
    }
}

struct AccessoryBattery: Identifiable, Sendable, Equatable {
    /// Stable across reads: the device plus which of its batteries this is.
    let id: String
    /// Shared by every part of one device; disconnect and alerts work per device.
    let deviceIdentifier: String
    let name: String
    let category: String?
    let part: AccessoryPart
    let percentage: Int
    let isCharging: Bool
    let lowWarnLevel: Int
    let transport: String?

    var displayName: String {
        guard let label = part.label else { return name }
        return "\(name) \(label)"
    }

    var isLow: Bool {
        percentage <= lowWarnLevel
    }

    var isBluetooth: Bool {
        transport?.hasPrefix("Bluetooth") == true
    }

    var symbol: String {
        switch category {
        case "Keyboard":
            return "keyboard"
        case "Mouse":
            return "computermouse"
        case "Trackpad":
            return "rectangle.and.hand.point.up.left"
        case "Headset", "Headphone", "Headphones":
            return "headphones"
        case "Speaker":
            return "hifispeaker"
        case "Game Controller", "Gamepad":
            return "gamecontroller"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}

enum AccessoryDisconnectState: Sendable, Equatable {
    case inProgress
    case failed
}
