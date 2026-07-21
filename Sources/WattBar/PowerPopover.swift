import AppKit
import SwiftUI

struct PowerPopover: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            chargingMetrics
            information
            Divider()
            appPowerSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { monitor.beginDetailUpdates() }
        .onDisappear { monitor.endDetailUpdates() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: monitor.snapshot.menuBarSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(monitor.snapshot.isCharging ? .green : .primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(monitor.snapshot.percentage)%")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(monitor.snapshot.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var chargingMetrics: some View {
        if monitor.snapshot.isCharging {
            HStack(spacing: 10) {
                MetricView(
                    title: "Battery intake",
                    value: PowerFormatting.watts(monitor.snapshot.chargingWatts),
                    symbol: "bolt.fill"
                )
                MetricView(
                    title: "Full in",
                    value: PowerFormatting.duration(minutes: monitor.snapshot.minutesToFull),
                    symbol: "clock"
                )
            }
        }
    }

    private var information: some View {
        VStack(spacing: 9) {
            InformationRow(
                symbol: "powerplug",
                label: "Power source",
                value: monitor.snapshot.powerSource
            )
            InformationRow(
                symbol: "arrow.triangle.2.circlepath",
                label: "Battery cycles",
                value: monitor.snapshot.cycleCount.map(String.init) ?? "—"
            )
        }
    }

    private var appPowerSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Highest app activity")
                    .font(.headline)
                Spacer()
                if monitor.isScanningApps {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if monitor.topApps.isEmpty && !monitor.isScanningApps {
                Text("No active apps detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(monitor.topApps.enumerated()), id: \.element.id) { index, app in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .trailing)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%% CPU", app.cpuPercent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("CPU activity is used as a power proxy; macOS does not publish per-app watts.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                monitor.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Quit WattBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct InformationRow: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}
