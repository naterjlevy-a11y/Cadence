import Foundation
import AppKit
import Carbon.HIToolbox
import Combine

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
    func hotkeyDidCancel()
}

/// Listens for the user's configured push-to-talk key globally using a
/// `CGEvent` tap. Supports two activation modes:
///
/// - `.holdToTalk`: hold the key, release to send.
/// - `.doubleTapToggle`: double-tap to start, single-tap or another
///   double-tap to stop. Useful when another app already owns hold-to-talk
///   on the same key (e.g. Claude Desktop's voice mode).
///
/// Modifier-style keys (right control / right option / fn / caps lock) are
/// detected via `flagsChanged` events. Function and "regular" keys are
/// detected via `keyDown` / `keyUp`.
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var capsLockOn = false

    /// True when the tap is alive and we're listening.
    private(set) var isListening = false

    // Tap-tracking state for `.doubleTapToggle`.
    private var lastKeyDownTime: Date?
    private var lastTapTime: Date?
    /// A single quick press+release counts as a "tap" only if shorter than this.
    private let tapMaxDuration: TimeInterval = 0.38

    // Hybrid-mode bookkeeping.
    private var hybridLatched = false   // True while hands-free (toggle-on) is active.
    private var hybridStartedFromHold = false   // True while the current recording was started by a long press.
    /// Scheduled work that finalizes a short-tap recording if a second tap
    /// never arrives within the double-tap window.
    private var pendingFinalizeWorkItem: DispatchWorkItem?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserCancelled),
            name: .mellotronUserCancelled,
            object: nil
        )
    }

    @objc private func handleUserCancelled() {
        userCancelledExternally()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    /// Called when the recording is cancelled externally (e.g. user clicked
    /// the X in the indicator). Resets internal state so the next keyDown
    /// starts a fresh session cleanly.
    func userCancelledExternally() {
        isRecording = false
        lastKeyDownTime = nil
        lastTapTime = nil
        if hybridLatched {
            NotificationCenter.default.post(name: .mellotronDidUnlatch, object: nil)
        }
        hybridLatched = false
        hybridStartedFromHold = false
        pendingFinalizeWorkItem?.cancel()
        pendingFinalizeWorkItem = nil
    }

    // MARK: - Public

    /// No-op — kept for backwards compatibility with existing call sites.
    /// We always read the current key fresh from preferences inside the
    /// event handler, so there is nothing to cache.
    func reloadFromPreferences() {}

    private var key: PushToTalkKey {
        UserPreferences.shared.pushToTalkKey
    }

    private var customKeyCode: Int {
        UserPreferences.shared.customKeyCode
    }

    private var activationMode: ActivationMode {
        UserPreferences.shared.activationMode
    }

    private var doubleTapWindow: TimeInterval {
        TimeInterval(max(150, UserPreferences.shared.doubleTapMaxIntervalMs)) / 1000
    }

    func start() {
        guard eventTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            Log.hotkey.error("Failed to create CGEvent tap. Likely missing Input Monitoring permission.")
            isListening = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
        Log.hotkey.info("HotkeyManager started: key=\(self.key.displayName, privacy: .public) mode=\(self.activationMode.rawValue, privacy: .public)")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isListening = false
        if isRecording {
            isRecording = false
            DispatchQueue.main.async { [weak self] in self?.delegate?.hotkeyDidCancel() }
        }
    }

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard !UserPreferences.shared.paused else { return }

        // Re-enable disabled tap if macOS times us out
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        // Allow Esc to cancel an in-progress recording.
        if isRecording && type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == kVK_Escape {
                Log.hotkey.info("Escape pressed during recording -> cancelling")
                isRecording = false
                lastKeyDownTime = nil
                lastTapTime = nil
                hybridLatched = false
                hybridStartedFromHold = false
                DispatchQueue.main.async { [weak self] in self?.delegate?.hotkeyDidCancel() }
                return
            }
        }

        switch key {
        case .rightControl, .rightOption, .capsLock, .fnGlobe:
            handleModifierStyleEvent(type: type, event: event)
        case .f5, .f6, .f13, .f14, .f15, .custom:
            handleKeyEvent(type: type, event: event)
        }
    }

    private func handleModifierStyleEvent(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch key {
        case .rightControl:
            guard keyCode == 62 else { return }
            handleKeyTransition(isPressed: flags.contains(.maskControl))
        case .rightOption:
            guard keyCode == 61 else { return }
            handleKeyTransition(isPressed: flags.contains(.maskAlternate))
        case .fnGlobe:
            guard keyCode == 63 else { return }
            handleKeyTransition(isPressed: flags.contains(.maskSecondaryFn))
        case .capsLock:
            guard keyCode == kVK_CapsLock else { return }
            // Caps lock generates flag changes on press AND release. We track
            // both transitions and feed them through the same press/release
            // pipeline as everything else.
            let isOn = flags.contains(.maskAlphaShift)
            if isOn != capsLockOn {
                capsLockOn = isOn
                handleKeyTransition(isPressed: isOn)
            }
        default: break
        }
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let target: Int
        switch key {
        case .f5: target = kVK_F5
        case .f6: target = kVK_F6
        case .f13: target = kVK_F13
        case .f14: target = kVK_F14
        case .f15: target = kVK_F15
        case .custom: target = customKeyCode
        default: target = -1
        }
        guard keyCode == target, target >= 0 else { return }

        if type == .keyDown {
            handleKeyTransition(isPressed: true)
        } else if type == .keyUp {
            handleKeyTransition(isPressed: false)
        }
    }

    /// The single chokepoint for both modifier and regular keys, after we've
    /// already filtered down to the target keycode.
    private func handleKeyTransition(isPressed: Bool) {
        switch activationMode {
        case .holdToTalk:
            handleHoldToTalk(isPressed: isPressed)
        case .doubleTapToggle:
            handleDoubleTap(isPressed: isPressed)
        case .hybrid:
            handleHybrid(isPressed: isPressed)
        }
    }

    private func handleHoldToTalk(isPressed: Bool) {
        if isPressed && !isRecording {
            startRecording()
        } else if !isPressed && isRecording {
            stopRecording()
        }
    }

    /// Double-tap state machine:
    ///   - keyDown remembers the press time.
    ///   - keyUp:
    ///       - If we held longer than `tapMaxDuration`, ignore (probably typing).
    ///       - Otherwise, this counts as a "tap". If a previous tap happened
    ///         within `doubleTapWindow`, treat it as a double-tap and toggle
    ///         recording. Otherwise just remember this tap.
    private func handleDoubleTap(isPressed: Bool) {
        if isPressed {
            lastKeyDownTime = Date()
            return
        }

        guard let down = lastKeyDownTime else { return }
        lastKeyDownTime = nil
        let heldFor = Date().timeIntervalSince(down)
        guard heldFor < tapMaxDuration else {
            // Too long to be a tap — reset the double-tap chain so a slow
            // hold doesn't combine with a later tap.
            lastTapTime = nil
            return
        }

        let now = Date()
        if let previous = lastTapTime, now.timeIntervalSince(previous) <= doubleTapWindow {
            lastTapTime = nil
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } else {
            lastTapTime = now
        }
    }

    /// Hybrid: hold to talk. A double-tap latches recording, and then a
    /// single tap stops + sends (Wispr-Flow-style toggle). We always start
    /// recording the instant the key goes down, then decide on release
    /// whether this was a hold (finalize), a first short tap (wait briefly
    /// to see if a second tap latches), a second tap (latch), or a single
    /// tap while latched (unlatch + send).
    private func handleHybrid(isPressed: Bool) {
        if isPressed {
            // Don't let a new keyDown clobber an already-recording session
            // (e.g. while latched). Just record the press time so we can
            // detect double-taps.
            lastKeyDownTime = Date()
            pendingFinalizeWorkItem?.cancel()
            pendingFinalizeWorkItem = nil
            if !isRecording {
                hybridStartedFromHold = true
                startRecording()
            }
            return
        }

        // Key released.
        guard let down = lastKeyDownTime else { return }
        lastKeyDownTime = nil
        let heldFor = Date().timeIntervalSince(down)

        // Long enough to be a hold (walkie-talkie). Finalize on release.
        if heldFor >= tapMaxDuration {
            if hybridLatched {
                // Holding while latched does NOT unlatch; keep recording.
                return
            }
            hybridStartedFromHold = false
            lastTapTime = nil
            if isRecording { stopRecording() }
            return
        }

        // ----- Short tap -----

        // If we're latched, a SINGLE short tap unlatches and sends.
        // (Wispr-Flow style: double-tap to lock in, tap once to paste.)
        if hybridLatched {
            lastTapTime = nil
            hybridLatched = false
            hybridStartedFromHold = false
            pendingFinalizeWorkItem?.cancel()
            pendingFinalizeWorkItem = nil
            NotificationCenter.default.post(name: .mellotronDidUnlatch, object: nil)
            Log.hotkey.info("Hybrid: single tap -> unlatched & sent")
            if isRecording { stopRecording() }
            return
        }

        // Not latched yet. This is either the first or the second short tap.
        let now = Date()
        if let previous = lastTapTime, now.timeIntervalSince(previous) <= doubleTapWindow {
            lastTapTime = nil
            hybridLatched = true
            hybridStartedFromHold = false
            pendingFinalizeWorkItem?.cancel()
            pendingFinalizeWorkItem = nil
            Log.hotkey.info("Hybrid: latched")
            NotificationCenter.default.post(name: .mellotronDidLatch, object: nil)
            return
        }

        lastTapTime = now
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Bail if the key is currently held or latch state changed.
            guard self.lastKeyDownTime == nil else { return }
            guard self.lastTapTime != nil else { return }
            guard !self.hybridLatched else { return }
            self.lastTapTime = nil
            if self.isRecording {
                self.hybridStartedFromHold = false
                self.stopRecording()
            }
        }
        pendingFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow + 0.02, execute: work)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        Log.hotkey.info("Recording start (mode=\(self.activationMode.rawValue, privacy: .public))")
        DispatchQueue.main.async { [weak self] in self?.delegate?.hotkeyDidPress() }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        Log.hotkey.info("Recording stop (mode=\(self.activationMode.rawValue, privacy: .public))")
        DispatchQueue.main.async { [weak self] in self?.delegate?.hotkeyDidRelease() }
    }
}

/// Helper to capture a single key press for the user's "set custom key" UI.
final class KeyCaptureController: ObservableObject {
    @Published var capturedKeyCode: Int? = nil
    @Published var capturedKeyDescription: String = "Press a key…"
    @Published var isCapturing: Bool = false

    private var monitor: Any?

    func start() {
        stop()
        isCapturing = true
        capturedKeyDescription = "Press a key…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                self.capture(keyCode: Int(event.keyCode), description: self.describeKey(keyCode: Int(event.keyCode)))
                return nil
            } else if event.type == .flagsChanged {
                self.capture(keyCode: Int(event.keyCode), description: self.describeKey(keyCode: Int(event.keyCode)))
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isCapturing = false
    }

    private func capture(keyCode: Int, description: String) {
        capturedKeyCode = keyCode
        capturedKeyDescription = description
        stop()
    }

    private func describeKey(keyCode: Int) -> String {
        switch keyCode {
        case 62: return "Right Control"
        case 61: return "Right Option"
        case 63: return "Fn / Globe"
        case kVK_CapsLock: return "Caps Lock"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        default: return "Key code \(keyCode)"
        }
    }
}
