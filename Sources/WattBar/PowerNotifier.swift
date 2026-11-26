import Foundation
import UserNotifications

enum PowerEvent: Equatable, Sendable {
    case pluggedIn
    case unplugged
    case fullyCharged
}

struct PowerNotificationContent: Equatable, Sendable {
    let title: String
    let body: String
}

enum PowerEventDetector {
    static func event(from previous: PowerSnapshot, to current: PowerSnapshot) -> PowerEvent? {
        // The adapter went away.
        if previous.isConnected && !current.isConnected {
            return .unplugged
        }
        // An adapter was connected.
        if !previous.isConnected && current.isConnected {
            return .pluggedIn
        }
        // Still connected and the battery just reached full.
        if current.isConnected && !previous.isFullyCharged && current.isFullyCharged {
            return .fullyCharged
        }
        return nil
    }
}

enum PowerNotificationText {
    static func content(for event: PowerEvent, snapshot: PowerSnapshot) -> PowerNotificationContent {
        switch event {
        case .pluggedIn:
            return PowerNotificationContent(
                title: "Plugged in",
                body: "\(snapshot.percentage)% · \(connectedDetail(snapshot))"
            )
        case .unplugged:
            return PowerNotificationContent(
                title: "On battery",
                body: "\(snapshot.percentage)% · \(batteryTimeLeft(snapshot))"
            )
        case .fullyCharged:
            return PowerNotificationContent(
                title: "Fully charged",
                body: "\(snapshot.percentage)% · on \(snapshot.powerSource)"
            )
        }
    }

    /// True once macOS has the estimate this event's message needs.
    static func hasEstimate(for event: PowerEvent, snapshot: PowerSnapshot) -> Bool {
        switch event {
        case .pluggedIn:
            return isPluggedInDetailKnown(snapshot)
        case .unplugged:
            return snapshot.minutesToEmpty != nil
        case .fullyCharged:
            return true
        }
    }

    private static func isPluggedInDetailKnown(_ snapshot: PowerSnapshot) -> Bool {
        // Full or not charging needs no estimate.
        if !snapshot.isCharging {
            return true
        }
        return snapshot.minutesToFull != nil
    }

    /// What a connected Mac's battery is doing, shared by notifications and the popover header.
    static func connectedDetail(_ snapshot: PowerSnapshot) -> String {
        // Already full: nothing to wait for.
        if snapshot.isFullyCharged {
            return "Fully charged"
        }
        // Connected but macOS is holding the charge (limit, heat or a weak adapter).
        if !snapshot.isCharging {
            return "Not charging"
        }
        // Charging, estimate still being calculated.
        guard let minutes = snapshot.minutesToFull else {
            return "Estimating time to full"
        }
        return "Full in \(PowerFormatting.duration(minutes: minutes))"
    }

    /// Time left on battery, shared by notifications and the popover header.
    static func batteryTimeLeft(_ snapshot: PowerSnapshot) -> String {
        // Estimate still being calculated.
        guard let minutes = snapshot.minutesToEmpty else {
            return "Estimating time left"
        }
        return "About \(PowerFormatting.duration(minutes: minutes)) left"
    }
}

@MainActor
final class PowerNotifier {
    private struct PendingNotification {
        let event: PowerEvent
        let deadline: Date
    }

    /// How long to wait for macOS to publish a time estimate before sending without one.
    private static let estimateWait: TimeInterval = 60
    private static let requestIdentifier = "com.donam.WattBar.power-event"

    private let center = UNUserNotificationCenter.current()
    private let presenter = NotificationPresenter()
    private var previous: PowerSnapshot?
    private var pending: PendingNotification?
    /// macOS tops a full battery up again while on AC; announce full once per connection.
    private var hasAnnouncedFull = false

    init() {
        center.delegate = presenter
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func observe(_ snapshot: PowerSnapshot) {
        defer { previous = snapshot }

        // The first reading is the baseline, not a change.
        guard let previous else { return }

        if let event = PowerEventDetector.event(from: previous, to: snapshot) {
            queue(event, snapshot: snapshot)
        }
        sendPendingWhenReady(snapshot)
    }

    private func queue(_ event: PowerEvent, snapshot: PowerSnapshot) {
        // A new connection starts a fresh "full" announcement; plugging in already full counts as it.
        if event == .pluggedIn || event == .unplugged {
            hasAnnouncedFull = snapshot.isFullyCharged
        }
        // Already told the user this connection is full.
        if event == .fullyCharged && hasAnnouncedFull {
            return
        }
        if event == .fullyCharged {
            hasAnnouncedFull = true
        }
        pending = PendingNotification(
            event: event,
            deadline: snapshot.measuredAt.addingTimeInterval(Self.estimateWait)
        )
    }

    private func sendPendingWhenReady(_ snapshot: PowerSnapshot) {
        // Nothing waiting.
        guard let pending else { return }

        let hasEstimate = PowerNotificationText.hasEstimate(for: pending.event, snapshot: snapshot)
        let isPastDeadline = snapshot.measuredAt >= pending.deadline
        // Keep waiting for the estimate until the deadline.
        guard hasEstimate || isPastDeadline else { return }

        self.pending = nil
        send(PowerNotificationText.content(for: pending.event, snapshot: snapshot))
    }

    private func send(_ text: PowerNotificationContent) {
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }
}

/// Shows banners even while the WattBar popover is open.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
