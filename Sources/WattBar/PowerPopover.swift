import AppKit
import SwiftUI

struct PowerPopover: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        PowerDetailView(
            snapshot: monitor.snapshot,
            accessories: monitor.accessories,
            disconnectStates: monitor.disconnectStates,
            topApps: monitor.topApps,
            isScanningApps: monitor.isScanningApps,
            onDisconnect: monitor.disconnect,
            onRefresh: monitor.refreshAll
        )
    }
}

/// The popover body, built from plain values so it renders the same in tests and previews.
struct PowerDetailView: View {
    let snapshot: PowerSnapshot
    let accessories: [AccessoryBattery]
    let disconnectStates: [String: AccessoryDisconnectState]
    let topApps: [AppPowerUse]
    let isScanningApps: Bool
    let onDisconnect: (AccessoryBattery) -> Void
    let onRefresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassGroup {
            tiles
        }
        .padding(12)
        .frame(width: 344)
        .animation(Motion.change(reduceMotion), value: snapshot)
        .animation(Motion.change(reduceMotion), value: accessories)
        .animation(Motion.change(reduceMotion), value: disconnectStates)
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            BatteryHeader(snapshot: snapshot)
            PowerFlowSection(snapshot: snapshot)
            if !accessories.isEmpty {
                DevicesSection(
                    accessories: accessories,
                    disconnectStates: disconnectStates,
                    onDisconnect: onDisconnect
                )
                .transition(.opacity)
            }
            AppActivitySection(apps: topApps, isScanning: isScanningApps)
            FooterBar(onRefresh: onRefresh)
        }
    }
}

// MARK: - Motion

private enum Motion {
    /// Values update every few seconds; a short ease-out keeps changes readable without lag.
    static func change(_ reduceMotion: Bool) -> Animation {
        guard reduceMotion else { return .easeOut(duration: 0.25) }
        return .linear(duration: 0.15)
    }

    static let hover = Animation.easeOut(duration: 0.15)
}

// MARK: - Battery header

private struct BatteryHeader: View {
    let snapshot: PowerSnapshot

    var body: some View {
        Platter(tint: glassTint) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(snapshot.percentage)")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(snapshot.percentage)))
                    Text("%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                Spacer(minLength: 8)

                StatusBadge(text: snapshot.statusText, symbol: statusSymbol, tint: statusTint)
            }

            Text(headerDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, -6)

            LevelBar(fraction: Double(snapshot.percentage) / 100, fill: levelFill)

            Text(snapshot.sourceFacts)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var headerDetail: String {
        // On battery the useful number is time left.
        guard snapshot.isConnected else {
            return PowerNotificationText.batteryTimeLeft(snapshot)
        }
        return PowerNotificationText.connectedDetail(snapshot)
    }

    private var statusSymbol: String {
        // Charging reads as a bolt, like the menu bar.
        if snapshot.isCharging {
            return "bolt.fill"
        }
        // Plugged in but the battery is still supplying power.
        if snapshot.isBatteryAssisting {
            return "arrow.up.forward"
        }
        // Plugged in and holding.
        if snapshot.isConnected {
            return "powerplug.portrait.fill"
        }
        return snapshot.batteryLevelSymbol
    }

    /// Neutral states keep clear glass; charging, assisting and low tint it so the state reads first.
    private var glassTint: Color? {
        // Plugged in or on battery with nothing to flag.
        guard statusTint != .primary else { return nil }
        return statusTint
    }

    private var levelFill: LinearGradient {
        // Idle reads as plain white, like the macOS battery icon.
        guard statusTint != .primary else {
            return LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [statusTint.opacity(0.75), statusTint], startPoint: .leading, endPoint: .trailing)
    }

    private var statusTint: Color {
        // Charging reads as green.
        if snapshot.isCharging {
            return .green
        }
        // Plugged in but the battery is still supplying power.
        if snapshot.isBatteryAssisting {
            return .orange
        }
        // Low on battery.
        if !snapshot.isConnected && snapshot.percentage <= 20 {
            return .red
        }
        return .primary
    }
}

private struct StatusBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
            .contentTransition(.opacity)
    }
}

// MARK: - Power flow

private struct PowerFlowSection: View {
    let snapshot: PowerSnapshot

    var body: some View {
        Platter {
            SectionTitle(title: "Power flow", trailing: snapshot.powerSourceSummary)

            if consumers.isEmpty {
                estimatedBatteryRow
            }

            if !consumers.isEmpty {
                FlowBar(segments: consumers, colors: colors)

                VStack(spacing: 6) {
                    ForEach(consumers) { segment in
                        FlowLegendRow(segment: segment, color: color(for: segment))
                    }
                }
            }

            if snapshot.isConnected, let discharge = snapshot.batteryDischargeWatts {
                Label("Battery adds \(PowerFormatting.watts(discharge)) to the adapter", systemImage: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private var consumers: [PowerFlowSegment] {
        snapshot.powerConsumers
    }

    private var colors: [String: Color] {
        var map: [String: Color] = [:]
        for segment in consumers {
            map[segment.id] = color(for: segment)
        }
        return map
    }

    private func color(for segment: PowerFlowSegment) -> Color {
        switch segment.kind {
        case .mac:
            return .blue
        case .battery:
            return .green
        case .device:
            return FlowPalette.device(at: deviceIndex(of: segment))
        }
    }

    /// Devices take colours in port order, so the first one is always orange.
    private func deviceIndex(of segment: PowerFlowSegment) -> Int {
        let devices = consumers.filter { $0.id.hasPrefix("device-") }
        return devices.firstIndex(of: segment) ?? 0
    }

    /// Macs without detailed telemetry only know the battery's own flow.
    private var estimatedBatteryRow: some View {
        HStack {
            Text("Battery")
                .foregroundStyle(.secondary)
            Spacer()
            Text(PowerFormatting.magnitudeWatts(snapshot.batteryPowerWatts))
                .monospacedDigit()
        }
        .font(.subheadline)
        .help("Detailed power telemetry is unavailable on this Mac; battery power is estimated from voltage and current.")
    }
}

private enum FlowPalette {
    static let devices: [Color] = [.orange, .purple, .pink, .teal]

    static func device(at index: Int) -> Color {
        devices[index % devices.count]
    }
}

/// One bar split by consumer, so the reader sees the share at a glance.
private struct FlowBar: View {
    let segments: [PowerFlowSegment]
    let colors: [String: Color]

    private static let gap: CGFloat = 2
    private static let minimumWidth: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: Self.gap) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(colors[segment.id, default: .gray].gradient)
                        .frame(width: width(of: segment, in: proxy.size.width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func width(of segment: PowerFlowSegment, in totalWidth: CGFloat) -> CGFloat {
        let total = segments.reduce(0) { $0 + $1.watts }
        // Nothing drawing power yet.
        guard total > 0 else { return Self.minimumWidth }
        let available = totalWidth - Self.gap * CGFloat(max(segments.count - 1, 0))
        return max(available * segment.watts / total, Self.minimumWidth)
    }
}

private struct FlowLegendRow: View {
    let segment: PowerFlowSegment
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(segment.label)
                .lineLimit(1)
            if let detail = segment.detail {
                Text(detail)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(PowerFormatting.watts(segment.watts))
                .monospacedDigit()
                .contentTransition(.numericText(value: segment.watts))
        }
        .font(.subheadline)
    }
}

// MARK: - Devices

private struct DevicesSection: View {
    let accessories: [AccessoryBattery]
    let disconnectStates: [String: AccessoryDisconnectState]
    let onDisconnect: (AccessoryBattery) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4)

    var body: some View {
        Platter {
            SectionTitle(title: "Devices", trailing: nil)

            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                ForEach(accessories) { accessory in
                    AccessoryRing(
                        accessory: accessory,
                        state: disconnectStates[accessory.deviceIdentifier],
                        onDisconnect: onDisconnect
                    )
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct AccessoryRing: View {
    let accessory: AccessoryBattery
    let state: AccessoryDisconnectState?
    let onDisconnect: (AccessoryBattery) -> Void

    @State private var isHovering = false

    private static let diameter: CGFloat = 46
    private static let lineWidth: CGFloat = 4

    var body: some View {
        VStack(spacing: 5) {
            ring
                .overlay(alignment: .topTrailing) { badge }

            VStack(spacing: 1) {
                Text("\(accessory.percentage)%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(accessory.percentage)))
                caption
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(state == .inProgress ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Motion.hover) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if accessory.isBluetooth {
                Button("Disconnect \(accessory.name)") {
                    onDisconnect(accessory)
                }
            }
        }
        .help(accessory.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessory.displayName), \(accessory.percentage) percent")
        .accessibilityAction(named: "Disconnect") {
            onDisconnect(accessory)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: Double(accessory.percentage) / 100)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .shadow(color: tint.opacity(0.45), radius: 3)
                .rotationEffect(.degrees(-90))
            Image(systemName: accessory.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            if state == .inProgress {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    @ViewBuilder
    private var badge: some View {
        // Hovering a Bluetooth device offers the one action it has.
        if isHovering && accessory.isBluetooth && state == nil {
            Button {
                onDisconnect(accessory)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 20, height: 20)
                    .modifier(GlassCircle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Disconnect \(accessory.name)")
            .offset(x: 5, y: -5)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        // Charging gets a bolt in the ring's corner, like the iOS Batteries widget.
        if !isHovering && accessory.isCharging {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(.green, in: Circle())
                .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if state == .failed {
            Text("Couldn't disconnect")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        if state != .failed {
            Text(accessory.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var tint: Color {
        // At or below the level macOS itself warns at, and not charging.
        if accessory.isLow && !accessory.isCharging {
            return .red
        }
        // Healthy or charging reads green, like the iOS Batteries widget.
        return .green
    }
}

// MARK: - App activity

private struct AppActivitySection: View {
    let apps: [AppPowerUse]
    let isScanning: Bool

    var body: some View {
        Platter {
            HStack(spacing: 6) {
                SectionTitle(title: "Most active apps", trailing: nil)
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Ranked by CPU use. macOS doesn't report watts per app, so CPU stands in for power.")
                Spacer()
                if isScanning {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            if apps.isEmpty && !isScanning {
                Text("No busy apps right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(apps) { app in
                    AppActivityRow(app: app, peak: peakCPU)
                }
            }
        }
    }

    private var peakCPU: Double {
        apps.map(\.cpuPercent).max() ?? 0
    }
}

private struct AppActivityRow: View {
    let app: AppPowerUse
    let peak: Double

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundlePath: app.bundlePath)
            Text(app.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            ShareBar(fraction: share)
                .frame(width: 44)
            Text(String(format: "%.0f%%", app.cpuPercent))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private var share: Double {
        // Nothing busy: draw an empty track.
        guard peak > 0 else { return 0 }
        return app.cpuPercent / peak
    }
}

private struct AppIcon: View {
    let bundlePath: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath))
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(Color.blue.gradient)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
            }
            .buttonBorderShape(.circle)
            .help("Read everything again now")
            .accessibilityLabel("Refresh")

            Spacer()

            Button("Quit WattBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .controlSize(.large)
        .modifier(GlassButtonStyle())
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}

// MARK: - Building blocks

private struct SectionTitle: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// A Control Center style platter: Liquid Glass on macOS 26+, a soft fill before that.
private struct Platter<Content: View>: View {
    var tint: Color?
    @ViewBuilder let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPlatter(cornerRadius: 24, tint: tint))
    }
}

/// Groups the tiles so macOS renders their glass together; tiles stay separate shapes.
private struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                content
            }
        } else {
            content
        }
    }
}

private struct GlassPlatter: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
    }

    /// Busy windows behind the panel bleed through clear glass; a faint window-colour tint keeps text legible.
    @available(macOS 26.0, *)
    private var glass: Glass {
        guard let tint else { return .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.45)) }
        return .regular.tint(tint.opacity(0.22))
    }
}

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.regularMaterial, in: Circle())
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

/// Pressable controls shrink slightly so the click feels heard.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LevelBar: View {
    let fraction: Double
    let fill: LinearGradient

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.1))
                Capsule()
                    .fill(fill)
                    .overlay(alignment: .top) {
                        // A thin highlight along the top so the fill reads as liquid, not paint.
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                    .frame(width: max(proxy.size.width * fraction, 10))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
