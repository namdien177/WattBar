import AppKit
import SwiftUI

struct PowerPopover: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            powerFlowSection
            Divider()
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
                .foregroundStyle(statusColor)
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

    private var statusColor: Color {
        if monitor.snapshot.isCharging {
            return .green
        }
        if monitor.snapshot.isBatteryAssisting {
            return .orange
        }
        return .primary
    }

    private var powerFlowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Power flow")
                .font(.headline)

            HStack(spacing: 10) {
                MetricView(
                    title: "Actual input",
                    value: PowerFormatting.watts(monitor.snapshot.inputWatts),
                    symbol: "powerplug.fill"
                )
                MetricView(
                    title: "Mac usage",
                    value: PowerFormatting.watts(monitor.snapshot.macPowerWatts),
                    symbol: "laptopcomputer"
                )
            }

            InformationRow(
                symbol: batteryFlowSymbol,
                label: batteryFlowLabel,
                value: PowerFormatting.magnitudeWatts(monitor.snapshot.batteryPowerWatts)
            )

            if monitor.snapshot.isCharging {
                InformationRow(
                    symbol: "clock",
                    label: "Full in",
                    value: PowerFormatting.duration(minutes: monitor.snapshot.minutesToFull)
                )
            }

            externalDevices

            if !monitor.snapshot.hasDetailedPowerTelemetry {
                Text("Detailed power telemetry is unavailable on this Mac; battery power is estimated.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var batteryFlowLabel: String {
        if monitor.snapshot.isCharging {
            return "Battery charging"
        }
        if monitor.snapshot.isBatteryAssisting {
            return "Battery assisting"
        }
        return "Battery flow"
    }

    private var batteryFlowSymbol: String {
        if monitor.snapshot.isCharging {
            return "arrow.down.to.line"
        }
        if monitor.snapshot.isBatteryAssisting {
            return "arrow.up.from.line"
        }
        return "minus"
    }

    private var externalDevices: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("External devices")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(PowerFormatting.watts(monitor.snapshot.externalPowerWatts))
                    .monospacedDigit()
            }

            if monitor.snapshot.externalDevices.isEmpty {
                Text("No powered USB-C devices detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(monitor.snapshot.externalDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .lineLimit(1)
                            Text(device.portLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(PowerFormatting.watts(device.watts))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
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
