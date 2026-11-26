import Foundation

struct ExternalPowerDevice: Identifiable, Sendable, Equatable {
    let portNumber: Int
    let name: String
    let watts: Double

    var id: Int { portNumber }
    var portLabel: String { "USB-C \(portNumber)" }
}

struct PowerSnapshot: Sendable, Equatable {
    let percentage: Int
    let isCharging: Bool
    let isConnected: Bool
    let batteryPowerWatts: Double?
    let inputWatts: Double?
    let macPowerWatts: Double?
    let externalDevices: [ExternalPowerDevice]
    let hasDetailedPowerTelemetry: Bool
    let minutesToFull: Int?
    let minutesToEmpty: Int?
    let isFullyCharged: Bool
    let powerSource: String
    let adapterRatingWatts: Int?
    let cycleCount: Int?
    let measuredAt: Date

    static let loading = PowerSnapshot(
        percentage: 0,
        isCharging: false,
        isConnected: false,
        batteryPowerWatts: nil,
        inputWatts: nil,
        macPowerWatts: nil,
        externalDevices: [],
        hasDetailedPowerTelemetry: false,
        minutesToFull: nil,
        minutesToEmpty: nil,
        isFullyCharged: false,
        powerSource: "Checking…",
        adapterRatingWatts: nil,
        cycleCount: nil,
        measuredAt: .distantPast
    )

    var statusText: String {
        if isCharging {
            return "Charging"
        }
        if isBatteryAssisting {
            return "Battery assisting"
        }
        if isConnected {
            return "Plugged in"
        }
        return "On battery"
    }

    var menuBarSymbol: String {
        // Charging shows the bolt so the state reads at a glance.
        if isCharging {
            return "battery.100percent.bolt"
        }
        return batteryLevelSymbol
    }

    var batteryLevelSymbol: String {
        if percentage >= 88 {
            return "battery.100percent"
        }
        if percentage >= 63 {
            return "battery.75percent"
        }
        if percentage >= 38 {
            return "battery.50percent"
        }
        if percentage >= 13 {
            return "battery.25percent"
        }
        return "battery.0percent"
    }

    var accessibilitySummary: String {
        "Battery \(percentage) percent, \(statusText.lowercased())"
    }

    var isBatteryAssisting: Bool {
        guard isConnected, let batteryPowerWatts else { return false }
        return batteryPowerWatts < -0.1
    }

    var chargingWatts: Double? {
        guard let batteryPowerWatts, batteryPowerWatts > 0.1 else { return nil }
        return batteryPowerWatts
    }

    var externalPowerWatts: Double {
        externalDevices.reduce(0) { $0 + $1.watts }
    }
}

enum PowerFormatting {
    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
    }

    static func magnitudeWatts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return watts(abs(value))
    }

    static func duration(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Estimating…" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}
