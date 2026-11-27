import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and a clear panel, so each tile is real Liquid Glass over the desktop
/// instead of glass stacked on the system popover's own background.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let monitor: PowerMonitor
    private let statusItem: NSStatusItem
    private let panel: DetailPanel
    private var snapshotSubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    /// The panel grows and shrinks with its content; its top edge stays under the menu bar.
    private var panelTop: CGFloat = 0

    private static let gapBelowMenuBar: CGFloat = 2
    private static let screenMargin: CGFloat = 6
    private static let fadeInSeconds: TimeInterval = 0.14

    init(monitor: PowerMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = DetailPanel(rootView: PowerPopover(monitor: monitor))
        super.init()

        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.closePanel()
        }

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageLeading

        snapshotSubscription = monitor.$snapshot.sink { [weak self] snapshot in
            MainActor.assumeIsolated {
                self?.updateButton(with: snapshot)
            }
        }
    }

    // MARK: Menu bar item

    private func updateButton(with snapshot: PowerSnapshot) {
        guard let button = statusItem.button else { return }

        let configuration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        let image = NSImage(systemSymbolName: snapshot.menuBarSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: "\(snapshot.percentage)%", attributes: [.font: font])
        button.setAccessibilityLabel(snapshot.accessibilitySummary)
    }

    @objc private func togglePanel() {
        // A second click on the menu bar item closes it, like a menu.
        if panel.isVisible {
            closePanel()
            return
        }
        openPanel()
    }

    // MARK: Panel

    private func openPanel() {
        monitor.beginDetailUpdates()
        positionPanel()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        // Opened many times a day: a short fade, no movement.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInSeconds
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
        }

        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel()
            }
        }
    }

    private func closePanel() {
        // Already closed, for example by Escape right after a click elsewhere.
        guard panel.isVisible else { return }

        panel.orderOut(nil)
        monitor.endDetailUpdates()
        statusItem.button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func positionPanel() {
        // The status item is not on screen yet (menu bar hidden or still loading).
        guard let buttonWindow = statusItem.button?.window, let screen = buttonWindow.screen else { return }

        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let anchor = buttonWindow.frame
        let visible = screen.visibleFrame
        let centredX = anchor.midX - size.width / 2
        let x = min(max(centredX, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)

        panelTop = anchor.minY - Self.gapBelowMenuBar
        panel.setFrame(NSRect(x: x, y: panelTop - size.height, width: size.width, height: size.height), display: false)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    func windowDidResize(_ notification: Notification) {
        // Content changed height (devices or apps loaded); keep the top edge pinned.
        panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: panelTop))
    }
}

/// A borderless, clear, non-activating panel: it takes key for Escape and hover without
/// pulling focus from the app in front.
final class DetailPanel: NSPanel {
    var onCancel: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
