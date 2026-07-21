import SwiftUI

@main
@MainActor
struct WattBarApp: App {
    @StateObject private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            PowerPopover(monitor: monitor)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: monitor.snapshot.menuBarSymbol)
                Text("\(monitor.snapshot.percentage)%")
                    .monospacedDigit()
            }
            .accessibilityLabel(monitor.snapshot.accessibilitySummary)
        }
        .menuBarExtraStyle(.window)
    }
}
