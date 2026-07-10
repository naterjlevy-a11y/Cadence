import Foundation
import AppKit
import Combine
import SwiftUI

/// Owns the status bar item and a custom NSPopover that hosts a SwiftUI panel.
/// One click on the menu-bar icon opens the panel — no nested menu navigation.
final class MenuBarController: NSObject {
    private let coordinator = DictationCoordinator.shared
    private let permissions = PermissionsManager.shared
    private let preferences = UserPreferences.shared

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var clickMonitor: Any?

    var openSettings: (() -> Void)?
    var openHistory: (() -> Void)?
    var openPermissionRepair: (() -> Void)?
    var quitApp: (() -> Void)?

    func install() {
        guard preferences.showMenuBarIcon else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = renderIcon(for: .idle)
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.contentViewController = makeHostingController()
        self.popover = popover

        coordinator.$stage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in self?.update(forStage: stage) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cadenceShowMenuPopover)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openPopoverIfNeeded() }
            .store(in: &cancellables)
    }

    private func openPopoverIfNeeded() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown { return }
        popover.contentViewController = makeHostingController()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installClickMonitor()
    }

    /// Hosting controller that sizes the popover to the SwiftUI content, so the
    /// popover hugs its panel and anchors flush under the menu-bar icon instead
    /// of using a stale fixed size.
    private func makeHostingController() -> NSHostingController<some View> {
        let controller = NSHostingController(rootView: makeRoot())
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    func remove() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        clickMonitor = nil
        popover?.close()
        popover = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    // MARK: - Popover

    private func makeRoot() -> some View {
        MenuBarPanelView(
            onOpenSettings: { [weak self] in self?.dismissAnd { self?.openSettings?() } },
            onOpenHistory: { [weak self] in self?.dismissAnd { self?.openHistory?() } },
            onOpenPermissionRepair: { [weak self] in self?.dismissAnd { self?.openPermissionRepair?() } },
            onQuit: { [weak self] in self?.dismissAnd { self?.quitApp?() } }
        )
        .cadenceThemed()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            tearDownClickMonitor()
        } else {
            // Re-mount the SwiftUI view so it pulls fresh state every time.
            popover.contentViewController = makeHostingController()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installClickMonitor()
        }
    }

    private func dismissAnd(_ work: @escaping () -> Void) {
        popover?.performClose(nil)
        tearDownClickMonitor()
        DispatchQueue.main.async(execute: work)
    }

    /// Close the popover when the user clicks anywhere outside of it.
    private func installClickMonitor() {
        tearDownClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.tearDownClickMonitor()
        }
    }

    private func tearDownClickMonitor() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        clickMonitor = nil
    }

    // MARK: - Icon

    private func update(forStage stage: DictationStage) {
        guard let button = statusItem?.button else { return }
        button.image = renderIcon(for: stage)
        // Always non-template — we paint the brand mello purple ourselves.
        button.image?.isTemplate = false
    }

    private func renderIcon(for stage: DictationStage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // The Cadence pill: capsule outline + waveform ticks (template).
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 4.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let midY = rect.midY
        let ticks: [(CGFloat, CGFloat)] = [(0.30, 2.2), (0.44, 3.6), (0.58, 1.6), (0.72, 2.8)]
        for (fx, half) in ticks {
            let x = rect.minX + fx * rect.width
            path.move(to: NSPoint(x: x, y: midY - half))
            path.line(to: NSPoint(x: x, y: midY + half))
        }
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let stroke: NSColor
        switch stage {
        case .recording: stroke = NSColor.systemRed
        case .failed: stroke = NSColor.systemOrange
        case .completed: stroke = NSColor.systemGreen
        default: stroke = NSColor(red: 0.486, green: 0.612, blue: 1.0, alpha: 1.0)
        }
        stroke.setStroke()
        path.stroke()

        if stage == .recording {
            NSColor.systemRed.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 4, y: rect.maxY - 1, width: 4, height: 4))
            dot.fill()
        }

        return image
    }
}

// MARK: - SwiftUI panel

private struct MenuBarPanelView: View {
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onOpenPermissionRepair: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var coordinator = DictationCoordinator.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @ObservedObject private var prefs = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if shouldShowPermissionBanner {
                Divider().opacity(0.14)
                permissionBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            Divider().opacity(0.14)

            VStack(spacing: 1) {
                rowButton(title: "Settings", glyph: "gearshape", action: onOpenSettings)
                rowButton(title: "History", glyph: "clock", action: onOpenHistory)
                rowButton(title: "Quit Cadence", glyph: "power", action: onQuit)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 300)
        .background(panelBackground)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    /// Show the orange "permissions need a refresh" banner only when
    /// something is actually missing **and** the user hasn't dismissed it for
    /// the current set of missing perms.
    private var shouldShowPermissionBanner: Bool {
        let missing = permissions.missingPermissions
        guard !missing.isEmpty else { return false }
        return prefs.permissionBannerDismissedSignature != Self.permissionsSignature(missing)
    }

    private static func permissionsSignature(_ items: [(name: String, kind: TCCKind)]) -> String {
        items.map(\.name).sorted().joined(separator: ",")
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandMark(size: 30, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cadence")
                    .font(.melloDisplay(18))
                    .tracking(-0.2)
                Text(coordinator.stage.userFacingDescription)
                    .font(.melloMono(9.5, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if coordinator.stage == .recording {
                MiniEQBars(loudness: Double(max(0, min(1, (Double(coordinator.liveLevel) + 60) / 50))))
                    .frame(width: 28, height: 14)
            }
        }
    }

    // MARK: - Banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text("Permissions need a refresh")
                    .font(.melloBody(12, weight: .semibold))
                Spacer()
                Button {
                    prefs.permissionBannerDismissedSignature = Self.permissionsSignature(permissions.missingPermissions)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide until the next permission change")
            }
            Text("macOS shows the toggle as ON but it's denied. Open Permission Repair to fix.")
                .font(.melloBody(10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Repair") { onOpenPermissionRepair() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                Button("Quick repair") { permissions.resetAllAndReprompt() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func rowButton(
        title: String,
        glyph: String,
        shortcut: String? = nil,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var panelBackground: some View {
        VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct MiniEQBars: View {
    let loudness: Double
    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let gap: CGFloat = 2
                let totalGap = gap * CGFloat(barCount - 1)
                let barWidth = (size.width - totalGap) / CGFloat(barCount)
                let midY = size.height / 2
                let maxH = size.height * 0.92

                for i in 0..<barCount {
                    let osc = sin(t * 6.4 + Double(i) * 0.61) * 0.5 + 0.5
                    let center = Double(barCount - 1) / 2.0
                    let weight = 1.0 - pow(abs(Double(i) - center) / center, 1.4) * 0.45
                    let amp = max(0.12, loudness * (0.55 + 0.45 * osc) * weight)
                    let h = max(2, CGFloat(amp) * maxH)
                    let x = CGFloat(i) * (barWidth + gap)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(Color.mello.opacity(0.55 + 0.45 * amp))
                    )
                }
            }
        }
    }
}

/// Wrap an `NSVisualEffectView` so the SwiftUI popover gets the proper
/// translucent vibrancy of a system menu.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
