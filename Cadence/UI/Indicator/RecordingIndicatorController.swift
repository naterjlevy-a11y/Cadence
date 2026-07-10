import Foundation
import AppKit
import SwiftUI
import Combine

/// A tiny, non-activating floating panel that shows the live recording
/// state. Inspired by Wispr Flow's pill — the size never changes between
/// states; only the contents fade.
final class RecordingIndicatorController {
    private var window: NSPanel?
    private var hostingView: NSHostingView<RecordingIndicatorView>?
    private var cancellables: Set<AnyCancellable> = []
    private var hideWorkItem: DispatchWorkItem?
    /// Maximum time the pill is allowed to stay visible in any non-recording
    /// stage. If the coordinator gets wedged we hide on our own rather than
    /// leaving a ghost pill floating on screen forever.
    private var safetyHideWork: DispatchWorkItem?

    private let coordinator = DictationCoordinator.shared

    // Compact Wispr-Flow-style pill, Cadence-tinted.
    private let panelWidth: CGFloat = 144
    private let panelHeight: CGFloat = 32

    private var toastWindow: NSPanel?
    private var toastHideWork: DispatchWorkItem?

    func install() {
        coordinator.$stage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                guard UserPreferences.shared.showFloatingIndicator else {
                    self?.hide()
                    return
                }
                self?.update(for: stage)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cadenceShowToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let message = (note.userInfo?["message"] as? String) ?? ""
                self?.showToast(message)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .preferencesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if !UserPreferences.shared.showFloatingIndicator {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        // Belt-and-suspenders: when the user cancels via any path, force
        // the pill down even if the stage signal hasn't propagated yet.
        NotificationCenter.default.publisher(for: .cadenceUserCancelled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.hide() }
            .store(in: &cancellables)
    }

    private func update(for stage: DictationStage) {
        switch stage {
        case .idle:
            hide()
        case .completed, .failed:
            show()
            scheduleHide(after: 1.2)
        case .cancelling:
            // Show briefly, then hide. The coordinator drops to .idle right
            // after cancel(), but if for any reason it doesn't, this still
            // tears the pill down.
            show()
            scheduleHide(after: 0.4)
        case .recording:
            // Hard reset both timers — recording must never auto-hide.
            hideWorkItem?.cancel()
            safetyHideWork?.cancel()
            show()
        default:
            // Any other in-flight stage. Keep the pill visible but arm a
            // safety net so we never get stuck >15s in a "processing" state.
            hideWorkItem?.cancel()
            show()
            armSafetyHide(after: 15.0)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let s = self.coordinator.stage
            if s == .idle || s == .completed || s == .failed || s == .cancelling {
                self.hide()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Hard timeout that fires regardless of stage. Cancelled whenever a
    /// new stage transition resets the pill or the user cancels.
    private func armSafetyHide(after seconds: TimeInterval) {
        safetyHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Only hide if we're NOT actively recording — recording can run
            // up to maximumRecordingSeconds and is exempt from this safety net.
            if self.coordinator.stage != .recording {
                Log.ui.warning("Indicator safety hide fired — stage=\(self.coordinator.stage.rawValue, privacy: .public)")
                self.hide()
            }
        }
        safetyHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func show() {
        if let window {
            if !window.isVisible { window.orderFrontRegardless() }
            return
        }

        let view = RecordingIndicatorView()
        let hosting = NSHostingView(rootView: view)
        let panelSize = NSSize(width: panelWidth, height: panelHeight)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .transient,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        // The panel accepts mouse events so the X badge is clickable, but
        // because it's a `.nonactivatingPanel`, clicks never steal focus from
        // whatever app the user is dictating into.
        panel.ignoresMouseEvents = false

        positionPanel(panel)

        let target = panel.frame.origin
        let start = NSPoint(x: target.x, y: target.y - 18)
        panel.setFrameOrigin(start)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }

        self.window = panel
        self.hostingView = hosting
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panelWidth / 2,
            y: frame.minY + 52
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Toast (bottom-right corner)

    private func showToast(_ message: String) {
        guard !message.isEmpty else { return }
        toastHideWork?.cancel()

        let hosting = NSHostingView(rootView: ToastView(message: message))
        let size = NSSize(width: 300, height: 44)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = toastWindow ?? {
            let p = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = false
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            return p
        }()
        panel.setContentSize(size)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 20, y: frame.minY + 24))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        toastWindow = panel

        let work = DispatchWorkItem { [weak self] in self?.hideToast() }
        toastHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func hideToast() {
        guard let panel = toastWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.toastWindow = nil
        })
    }

    private func hide() {
        guard let window else { return }
        let origin = window.frame.origin
        let target = NSPoint(x: origin.x, y: origin.y - 14)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
            window.animator().alphaValue = 0
            window.animator().setFrameOrigin(target)
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
        })
    }
}

// MARK: - Toast view

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.mello)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.melloSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.mello.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(2)
    }
}

// MARK: - SwiftUI

private struct RecordingIndicatorView: View {
    @ObservedObject private var coordinator = DictationCoordinator.shared

    /// Smoothed loudness, 0…1. Drives the bouncing EQ bars.
    @State private var loudness: Double = 0
    @State private var breathing: Bool = false
    @State private var isLatched: Bool = false

    private let pillWidth: CGFloat = 144
    private let pillHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            leftBadge
                .frame(width: 18, height: 18)
                .padding(.leading, 7)
                .padding(.trailing, 4)
                .contentShape(Circle())
                .onTapGesture {
                    DictationCoordinator.shared.cancel()
                    // Force the pill down even if cancel() doesn't reach
                    // `.idle` immediately (race with in-flight work).
                    NotificationCenter.default.post(name: .cadenceUserCancelled, object: nil)
                }
                .help(isLatched ? "Cancel (latched — single-tap Option to send)" : "Cancel")

            // The visualizer always lives in the same slot — recording,
            // processing, completed, failed all use the same EQ bars,
            // tinted by stage. No text labels.
            EQBars(loudness: loudness, color: accentColor, intensity: visualizerIntensity)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .allowsHitTesting(false)

            rightBadge
                .frame(width: 18, height: 18)
                .padding(.leading, 4)
                .padding(.trailing, 7)
                .contentShape(Circle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .cadenceShowMenuPopover, object: nil)
                }
                .help("Open Cadence menu")
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(background)
        .compositingGroup()
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: coordinator.stage)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onReceive(coordinator.$liveLevel.receive(on: DispatchQueue.main)) { level in
            // Convert dB (-60..0) to 0..1, ease toward target so the bars
            // breathe with the sound rather than snapping.
            let raw = max(0, min(1, (Double(level) + 60) / 50))
            let eased = pow(raw, 0.7)
            withAnimation(.easeOut(duration: 0.10)) {
                loudness = isRecording ? eased : 0
            }
        }
        .onChange(of: coordinator.stage) { _, new in
            if new == .recording { loudness = 0 }
            if new == .idle { isLatched = false; loudness = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceDidLatch)) { _ in
            isLatched = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceDidUnlatch)) { _ in
            isLatched = false
        }
    }

    // MARK: - Background

    private var background: some View {
        // No drop-shadows — they show as dark halos against pitch-black IDEs
        // and terminals. Just a clean capsule with a flat purple hairline that
        // brightens while recording.
        Capsule(style: .continuous)
            .fill(Color.melloSurface)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.mello.opacity(isRecording ? 0.55 : 0.18), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.25), value: isRecording)
    }

    // MARK: - Badges

    private var leftBadge: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(isLatched ? Color.mello.opacity(0.28) : Color.white.opacity(0.16))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            if isLatched {
                Circle()
                    .fill(Color.mello)
                    .frame(width: 5, height: 5)
                    .offset(x: 3, y: -3)
            }
        }
    }

    private var rightBadge: some View {
        ZStack {
            Circle().fill(rightBadgeFill)
            Image(systemName: rightSymbol)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(rightSymbolColor)
                .contentTransition(.symbolEffect(.replace.downUp))
                .id("right-\(rightSymbol)")
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: rightBadgeFill)
    }

    private var rightBadgeFill: Color {
        switch coordinator.stage {
        case .failed: return Color.orange.opacity(0.95)
        case .completed: return Color.green.opacity(0.95)
        case .recording: return Color.mello.opacity(0.95)
        default: return Color.white.opacity(0.92)
        }
    }

    private var rightSymbol: String {
        switch coordinator.stage {
        case .recording: return "waveform"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .pasting, .openingDestination, .resolvingDestination, .waitingForDestination:
            return "arrow.right"
        case .cancelling: return "xmark"
        default: return "ellipsis"
        }
    }

    private var rightSymbolColor: Color {
        switch coordinator.stage {
        case .recording, .failed, .completed: return Color.white
        default: return Color.black.opacity(0.85)
        }
    }

    // MARK: - State helpers

    private var isRecording: Bool {
        coordinator.stage == .recording
    }

    /// Drives the EQ bars' base amplitude when there's no live audio
    /// (idle pulse, processing pulse, completed pulse).
    private var visualizerIntensity: Double {
        switch coordinator.stage {
        case .recording: return 1.0
        case .completed: return 0.55
        case .failed: return 0.45
        default: return 0.18
        }
    }

    private var accentColor: Color {
        switch coordinator.stage {
        case .recording: return Color.mello
        case .completed: return .green
        case .failed: return .orange
        default: return Color.melloDeep
        }
    }
}

// MARK: - EQ bars (Apple-Music-style, position-stable)

private struct EQBars: View {
    /// 0…1, eased toward the live mic level.
    let loudness: Double
    let color: Color
    /// Multiplier on the per-bar idle motion. 1.0 = recording, lower for
    /// the idle / processing / completed states.
    let intensity: Double

    private let barCount = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let gap: CGFloat = 2
                let totalGap = gap * CGFloat(barCount - 1)
                let barWidth = (size.width - totalGap) / CGFloat(barCount)
                let midY = size.height / 2
                let maxH = size.height * 0.92

                for i in 0..<barCount {
                    // Each bar oscillates with its own phase so the row
                    // bounces organically without any horizontal motion.
                    let phaseA = Double(i) * 0.61
                    let phaseB = Double(i) * 1.13
                    let oscA = sin(t * 6.4 + phaseA) * 0.5 + 0.5
                    let oscB = sin(t * 3.7 + phaseB) * 0.5 + 0.5
                    let osc = oscA * 0.65 + oscB * 0.35

                    // Bell-curve weighting so middle bars react more than
                    // the outer ones, the way Wispr Flow's bars do.
                    let center = Double(barCount - 1) / 2.0
                    let weight = 1.0 - pow(abs(Double(i) - center) / center, 1.4) * 0.45

                    let live = loudness * (0.55 + 0.45 * osc) * weight
                    let idle = (0.10 + 0.18 * osc) * weight
                    let amp = max(0.10, intensity > 0.85 ? max(idle * 0.6, live) : idle * intensity * 1.4)

                    let h = max(2, CGFloat(amp) * maxH)
                    let x = CGFloat(i) * (barWidth + gap)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color.opacity(0.55 + 0.45 * amp))
                    )
                }
            }
        }
    }
}
