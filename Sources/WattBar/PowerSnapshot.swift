import Foundation

struct PowerSnapshot: Sendable, Equatable {
    let percentage: Int
    let isCharging: Bool
    let isConnected: Bool
    let chargingWatts: Double?
    let minutesToFull: Int?
    let powerSource: String
    let adapterRatingWatts: Int?
    let cycleCount: Int?
    let measuredAt: Date

    static let loading = PowerSnapshot(
        percentage: 0,
        isCharging: false,
        isConnected: false,
        chargingWatts: nil,
        minutesToFull: nil,
        powerSource: "Checking…",
        adapterRatingWatts: nil,
        cycleCount: nil,
        measuredAt: .distantPast
    )

    var statusText: String {
        if isCharging {
            return "Charging"
        }
        if isConnected {
            return "Plugged in"
        }
        return "On battery"
    }

    var menuBarSymbol: String {
        if isCharging {
            return "bolt.fill"
        }
        if isConnected {
            return "powerplug.fill"
        }
        return "battery.50percent"
    }

    var accessibilitySummary: String {
        "Battery \(percentage) percent, \(statusText.lowercased())"
    }
}

enum PowerFormatting {
    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
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
