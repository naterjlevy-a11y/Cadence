import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import Combine
import Speech

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case restricted
    case unknown
}

/// Tracks the macOS permissions Cadence depends on and exposes
/// `@Published` state that the onboarding and settings UIs observe.
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var microphone: PermissionStatus = .unknown
    @Published private(set) var accessibility: PermissionStatus = .unknown
    @Published private(set) var inputMonitoring: PermissionStatus = .unknown
    @Published private(set) var speechRecognition: PermissionStatus = .unknown

    private var pollTimer: Timer?

    private init() {
        refreshAll()
    }

    /// Refresh all permission states without prompting.
    func refreshAll() {
        microphone = currentMicrophoneStatus()
        accessibility = currentAccessibilityStatus(prompt: false)
        // `inputMonitoring` is no longer polled. This ran
        // `CGPreflightListenEventAccess()` on every tick — every 1s with a
        // settings or onboarding pane open, every 2s otherwise — for a
        // permission the app doesn't use and doesn't show anywhere live.
        speechRecognition = currentSpeechRecognitionStatus()
    }

    /// Begin polling system permission state every second. Used while the
    /// onboarding window is visible so we can advance once the user grants
    /// permission in System Settings.
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Microphone

    func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }

    func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphone = granted ? .granted : .denied
                completion(granted)
            }
        }
    }

    // MARK: - Speech Recognition

    func currentSpeechRecognitionStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }

    func requestSpeechRecognition(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                let granted = (status == .authorized)
                self?.speechRecognition = granted ? .granted : .denied
                completion(granted)
            }
        }
    }

    // MARK: - Accessibility

    /// Prompts only if `prompt` is true. macOS will show its system trust prompt
    /// the first time we call with prompt=true, which is what the onboarding
    /// "Open Accessibility Settings" button uses.
    @discardableResult
    func currentAccessibilityStatus(prompt: Bool) -> PermissionStatus {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    /// System Settings caches the Accessibility / Input-Monitoring list. If it's
    /// already open when we register, it shows a stale snapshot WITHOUT Cadence,
    /// forcing the user to the "+" button. Quitting it first guarantees a fresh
    /// list that includes us.
    private func quitSystemSettings() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences") {
            app.terminate()
        }
    }

    /// Attempt a real accessibility read. Like the event-tap trick for Input
    /// Monitoring, the *attempt* is what registers Cadence in the Accessibility
    /// list — requesting the prompt alone doesn't reliably add it on macOS 26.
    private func registerAsAccessibilityConsumer() {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
    }

    /// Attempt a throwaway listen-only event tap. It returns non-nil only when
    /// authorized, but the *attempt itself* is what registers Cadence as an
    /// event-tap consumer in the Input Monitoring list — this is the missing
    /// registration trigger.
    private func registerAsEventTapConsumer() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func openAccessibilitySettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Registers Cadence in the Accessibility list (unchecked).
        _ = currentAccessibilityStatus(prompt: true)
        // The actual AX read is the real registration trigger (mirrors the
        // event-tap trick that fixed Input Monitoring).
        registerAsAccessibilityConsumer()
        // Refresh the pane so the just-added entry actually shows.
        quitSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        startPolling()
    }

    // MARK: - Input Monitoring

    func currentInputMonitoringStatus() -> PermissionStatus {
        // We listen via a CGEventTap, so the matching permission is the
        // CoreGraphics "listen event" access — NOT IOHID. Using the wrong API
        // pair is why the app failed to appear in the Input Monitoring list.
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess() ? .granted : .denied
        }
        return .granted
    }

    func requestInputMonitoring() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
        // The actual tap attempt is what lists us in the Input Monitoring pane.
        registerAsEventTapConsumer()
        quitSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
        startPolling()
    }

    // MARK: - Repair (stuck TCC after ad-hoc rebuild)

    /// Which permissions are currently NOT granted, in display order.
    /// Only the two permissions Cadence actually requires. Speech Recognition
    /// is deferred (on-device only) and Input Monitoring was dropped entirely
    /// (the hotkey now uses an NSEvent monitor gated on Accessibility). So a
    /// user with Mic + Accessibility is fully set up — no "repair" needed.
    var missingPermissions: [(name: String, kind: TCCKind)] {
        var out: [(String, TCCKind)] = []
        if microphone != .granted { out.append(("Microphone", .microphone)) }
        if accessibility != .granted { out.append(("Accessibility", .accessibility)) }
        return out
    }

    /// Reset stale TCC entries for the given service, then open System
    /// Settings so the user can grant fresh. This fixes the very common
    /// "toggle is on but the system still says denied" situation that
    /// happens after every Xcode rebuild of an ad-hoc-signed dev build —
    /// TCC keeps the visible entry but invalidates it because the new
    /// binary's signature doesn't match.
    @discardableResult
    func resetAndReprompt(_ kind: TCCKind) -> Bool {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.natelevy.cadence"
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", kind.tccService, bundleId]
        do {
            try task.run()
            task.waitUntilExit()
            Log.app.info("tccutil reset \(kind.tccService, privacy: .public) → exit=\(task.terminationStatus, privacy: .public)")
        } catch {
            Log.app.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // After a reset the next call to the matching API (re-)prompts.
        switch kind {
        case .microphone:
            requestMicrophone { _ in }
        case .speech:
            requestSpeechRecognition { _ in }
        case .accessibility:
            openAccessibilitySettings()
        case .inputMonitoring:
            requestInputMonitoring()
        }
        startPolling()
        return true
    }

    /// Reset all stale TCC entries at once. Useful for the "Repair all" button.
    @discardableResult
    func resetAllAndReprompt() -> Bool {
        // Input Monitoring is deliberately absent. The hotkey moved from a
        // CGEventTap to NSEvent monitors, so nothing in Cadence needs it — but
        // this list still included it, which meant "Repair all" ran
        // `tccutil reset ListenEvent`, created a throwaway event tap purely to
        // register the app in the Input Monitoring list, and opened that pane
        // in System Settings. A two-permission app was actively asking for a
        // third one it never uses.
        let services: [TCCKind] = [.microphone, .speech, .accessibility]
        var allOK = true
        for kind in services {
            if !resetAndReprompt(kind) { allOK = false }
        }
        return allOK
    }
}

/// The small set of TCC services Cadence talks to. The raw string is
/// the service identifier `tccutil reset` understands.
enum TCCKind {
    case microphone
    case speech
    case accessibility
    case inputMonitoring

    var tccService: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "SpeechRecognition"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "ListenEvent"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

// MARK: - IOKit shim
// These constants/functions live in IOKit. We declare minimal stubs so we
// can call them from Swift without importing the full IOKit umbrella.
import IOKit.hid

