import AppKit
import SwiftUI

struct PowerPopover: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            powerFlowModule
            informationModule
            appActivityModule
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { monitor.beginDetailUpdates() }
        .onDisappear { monitor.endDetailUpdates() }
    }

    // MARK: Header

    private var header: some View {
        GlassModule {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: monitor.snapshot.menuBarSymbol)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(monitor.snapshot.percentage)%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(monitor.snapshot.statusText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(statusColor)
                    }
                    Text(headerDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            LevelBar(
                fraction: Double(monitor.snapshot.percentage) / 100,
                tint: statusColor
            )
        }
    }

    private var headerDetail: String {
        // On battery the useful number is time left.
        if !monitor.snapshot.isConnected {
            return PowerNotificationText.batteryTimeLeft(monitor.snapshot)
        }
        return PowerNotificationText.connectedDetail(monitor.snapshot)
    }

    private var statusColor: Color {
        // Charging reads as green.
        if monitor.snapshot.isCharging {
            return .green
        }
        // Plugged in but the battery is still supplying power.
        if monitor.snapshot.isBatteryAssisting {
            return .orange
        }
        // Low on battery.
        if !monitor.snapshot.isConnected && monitor.snapshot.percentage <= 20 {
            return .red
        }
        return .primary
    }

    // MARK: Power flow

    private var powerFlowModule: some View {
        GlassModule(title: "Power flow") {
            HStack(spacing: 8) {
                MetricTile(
                    title: "Input",
                    value: PowerFormatting.watts(monitor.snapshot.inputWatts),
                    symbol: "powerplug.portrait.fill"
                )
                MetricTile(
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
        VStack(alignment: .leading, spacing: 6) {
            InformationRow(
                symbol: "cable.connector",
                label: "External devices",
                value: PowerFormatting.watts(monitor.snapshot.externalPowerWatts)
            )

            if monitor.snapshot.externalDevices.isEmpty {
                Text("No powered USB-C devices detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 26)
            }

            ForEach(monitor.snapshot.externalDevices) { device in
                ExternalDeviceRow(device: device)
            }
        }
    }

    // MARK: Information

    private var informationModule: some View {
        GlassModule {
            InformationRow(
                symbol: "bolt.horizontal",
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

    // MARK: App activity

    private var appActivityModule: some View {
        GlassModule(title: "Highest app activity", isBusy: monitor.isScanningApps) {
            if monitor.topApps.isEmpty && !monitor.isScanningApps {
                Text("No active apps detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(monitor.topApps.enumerated()), id: \.element.id) { index, app in
                AppActivityRow(rank: index + 1, app: app)
            }

            Text("CPU activity is used as a power proxy; macOS does not publish per-app watts.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                monitor.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button("Quit WattBar") {
                NSApplication.shared.terminate(nil)
            }
        }
        .controlSize(.small)
        .modifier(GlassButtonStyle())
        .padding(.horizontal, 2)
    }
}

// MARK: - Building blocks

/// A Control Center style platter: Liquid Glass on macOS 26+, a soft fill before that.
private struct GlassModule<Content: View>: View {
    var title: String?
    var isBusy = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPlatter(cornerRadius: 18))
    }
}

private struct GlassPlatter: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(
                .quaternary.opacity(0.6),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

private struct GlassButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct LevelBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(proxy.size.width * fraction, 6))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct ExternalDeviceRow: View {
    let device: ExternalPowerDevice

    var body: some View {
        HStack(spacing: 8) {
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
        .padding(.leading, 26)
    }
}

private struct AppActivityRow: View {
    let rank: Int
    let app: AppPowerUse

    var body: some View {
        HStack {
            Text("\(rank)")
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
        .font(.subheadline)
    }
}
