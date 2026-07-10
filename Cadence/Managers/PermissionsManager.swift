import Foundation
import AppKit
import AVFoundation
import ApplicationServices
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
        inputMonitoring = currentInputMonitoringStatus()
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

    func openAccessibilitySettings() {
        // First request a prompt so macOS adds Cadence to the list.
        _ = currentAccessibilityStatus(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    // MARK: - Input Monitoring

    func currentInputMonitoringStatus() -> PermissionStatus {
        // IOHIDCheckAccess is the documented API but is in IOKit and not always
        // accurate for our use case. We use a probe: try to create a tap. If it
        // succeeds we have permission, otherwise we don't.
        if #available(macOS 10.15, *) {
            let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            switch access {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            case kIOHIDAccessTypeUnknown: return .notDetermined
            default: return .unknown
            }
        }
        return .granted
    }

    func requestInputMonitoring() {
        // Triggers the system prompt to add Cadence to the list.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    // MARK: - Repair (stuck TCC after ad-hoc rebuild)

    /// Which permissions are currently NOT granted, in display order.
    var missingPermissions: [(name: String, kind: TCCKind)] {
        var out: [(String, TCCKind)] = []
        if microphone != .granted { out.append(("Microphone", .microphone)) }
        if speechRecognition != .granted { out.append(("Speech Recognition", .speech)) }
        if accessibility != .granted { out.append(("Accessibility", .accessibility)) }
        if inputMonitoring != .granted { out.append(("Input Monitoring", .inputMonitoring)) }
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
        let services: [TCCKind] = [.microphone, .speech, .accessibility, .inputMonitoring]
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

