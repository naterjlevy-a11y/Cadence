import SwiftUI
import AppKit

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case howItWorks
    case permissions
    case pushToTalkKey
    case test
    case done

    var id: Int { rawValue }
}

struct OnboardingFlowView: View {
    @State private var step: OnboardingStep = OnboardingStep(rawValue: UserPreferences.shared.onboardingStep) ?? .welcome
    @StateObject private var prefs = UserPreferences.shared
    @StateObject private var permissions = PermissionsManager.shared

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 24)
                    .padding(.horizontal, 36)
                stepDots
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 700, height: 540)
        .cadenceThemed()
        .onAppear {
            permissions.startPolling()
            // If we were in the middle of granting Accessibility / Input
            // Monitoring and macOS asked us to quit & reopen, fast-forward
            // to the next step that still needs work.
            autoAdvancePastGranted()
        }
        .onDisappear { permissions.stopPolling() }
        .onChange(of: step) { _, newStep in
            prefs.onboardingStep = newStep.rawValue
        }
    }

    /// On a fresh launch, if a step is already satisfied (e.g. accessibility
    /// was just granted via a system restart), jump past it.
    private func autoAdvancePastGranted() {
        guard step == .permissions else { return }
        if permissions.microphone == .granted,
           permissions.speechRecognition == .granted,
           permissions.accessibility == .granted,
           permissions.inputMonitoring == .granted {
            step = .pushToTalkKey
        }
    }

    private var background: some View {
        Color.melloInk.ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep(onContinue: { step = .howItWorks })
        case .howItWorks:
            HowItWorksStep(onContinue: { step = .permissions })
        case .permissions:
            PermissionsStep(onContinue: { step = .pushToTalkKey })
        case .pushToTalkKey:
            PushToTalkKeyStep(onContinue: { step = .test })
        case .test:
            TestStep(onContinue: { step = .done })
        case .done:
            DoneStep(onClose: { close() })
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { s in
                Capsule()
                    .fill(s == step ? Color.mello : Color.white.opacity(0.18))
                    .frame(width: s == step ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
            }
        }
    }

    private func close() {
        UserPreferences.shared.hasCompletedOnboarding = true
        NSApp.keyWindow?.close()
    }
}

// MARK: - Steps

private struct StepShell<Content: View>: View {
    let title: String
    let subtitle: String
    let primaryLabel: String?
    let secondaryLabel: String?
    let onPrimary: (() -> Void)?
    let onSecondary: (() -> Void)?
    let primaryDisabled: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        primaryLabel: String? = "Continue",
        secondaryLabel: String? = nil,
        primaryDisabled: Bool = false,
        onPrimary: (() -> Void)? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.primaryDisabled = primaryDisabled
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                renderedTitle
                Text(subtitle)
                    .font(.melloBody(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                if let secondaryLabel, let onSecondary {
                    Button(secondaryLabel, action: onSecondary)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Spacer()
                if let primaryLabel, let onPrimary {
                    Button(action: onPrimary) {
                        Text(primaryLabel)
                            .font(.melloBody(13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryDisabled)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Render the step title using Instrument Serif, treating an asterisk-wrapped
    /// run as italic ("Hold your *key*"). This lets each step have its own
    /// hand-tuned emphasis without needing a custom AttributedString per step.
    @ViewBuilder private var renderedTitle: some View {
        let pieces = title.split(separator: "*", omittingEmptySubsequences: false)
        if pieces.count > 1 {
            pieces.enumerated().reduce(Text("")) { acc, pair in
                let (i, piece) = pair
                let isItalic = i % 2 == 1
                let font = isItalic ? Font.melloDisplayItalic(30) : Font.melloDisplay(30)
                return acc + Text(String(piece)).font(font)
            }
            .tracking(-0.4)
            .foregroundStyle(.primary)
        } else {
            Text(title)
                .font(.melloDisplay(30))
                .tracking(-0.4)
        }
    }
}

private struct WelcomeStep: View {
    let onContinue: () -> Void
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        StepShell(
            title: "Talk to any app on your *Mac*.",
            subtitle: "Hold a key. Speak naturally. Release. Cadence transcribes, polishes, and pastes — Claude, ChatGPT, Docs, anywhere.",
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            onPrimary: onContinue,
            onSecondary: secondaryLabel == nil ? nil : onContinue
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FeatureTile(glyph: "waveform", title: "Push to talk", caption: "Hold one key")
                    FeatureTile(glyph: "wand.and.sparkles", title: "AI polish", caption: "Lists, names, grammar")
                    FeatureTile(glyph: "rectangle.stack.fill", title: "Anywhere", caption: "Any app or website")
                }

                AccountTile()

                if auth.isSignedIn && !auth.isAnonymous {
                    if auth.plan == "pro" {
                        Text("You're on Cadence Pro — unlimited dictation is active.")
                            .font(.melloBody(11))
                            .foregroundStyle(.green)
                    } else {
                        Text("Free tier active (~3 hours/month). Upgrade anytime in Settings → Account.")
                            .font(.melloBody(11))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("Sign in or create account") {
                            SignInWindowController.shared.present()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Continue as guest") {
                            onContinue()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Google, GitHub, or email + password. Guest mode works without signing in.")
                        .font(.melloBody(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadenceAuthCompleted)) { _ in }
        }
    }

    private var primaryLabel: String {
        if auth.isSignedIn && !auth.isAnonymous { return "Continue" }
        return "Set up Cadence"
    }

    private var secondaryLabel: String? {
        if auth.isSignedIn && !auth.isAnonymous { return nil }
        return nil
    }
}

private struct FeatureTile: View {
    let glyph: String
    let title: String
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.mello)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.mello.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.melloBody(13, weight: .semibold))
                Text(caption)
                    .font(.melloMono(10.5, weight: .medium))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct AccountTile: View {
    @ObservedObject private var auth = AuthService.shared
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: badgeIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.mello))
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(.melloBody(14, weight: .semibold))
                Text(secondary)
                    .font(.melloBody(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    private var badgeIcon: String {
        if !auth.isSignedIn { return "person.crop.circle.badge.plus" }
        if auth.isAnonymous { return "person.crop.circle.dashed" }
        return "checkmark.seal.fill"
    }
    private var primary: String {
        if !auth.isSignedIn { return "Not signed in" }
        if auth.isAnonymous { return "Guest session" }
        return auth.userEmail ?? "Signed in"
    }
    private var secondary: String {
        if !auth.isSignedIn { return "Sign in with Google, GitHub, or email." }
        if auth.isAnonymous { return "Free tier active — sign in to keep your account." }
        if auth.plan == "pro" { return "Cadence Pro — unlimited dictation." }
        return "Plan: \(auth.plan) · Free tier ready."
    }
}

private struct HowItWorksStep: View {
    let onContinue: () -> Void
    var body: some View {
        StepShell(
            title: "How it *works*.",
            subtitle: "Three steps. Nothing else to think about.",
            onPrimary: onContinue
        ) {
            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, title: "Hold your key", description: "Anywhere on your Mac.")
                StepRow(number: 2, title: "Say where it goes", description: "“Hey Claude…”, “Hey Google Docs…”, or just speak.")
                StepRow(number: 3, title: "Release to send", description: "Cadence opens the destination, cleans up the text, and pastes.")

                ExampleBox(
                    raw: "Hey Claude, help me write a product spec for this idea.",
                    cleaned: "Help me write a product spec for this idea."
                )
                .padding(.top, 8)
            }
        }
    }
}

private struct PermissionsStep: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    let onContinue: () -> Void

    var body: some View {
        StepShell(
            title: "Grant *permissions*.",
            subtitle: "Cadence needs four macOS permissions. Grant each one, then continue — you can fix stale toggles later with Permission Repair.",
            primaryLabel: "Continue",
            onPrimary: onContinue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingPermissionRow(
                    title: "Microphone",
                    detail: "Records only while you hold your key.",
                    state: permissions.microphone,
                    grant: { permissions.requestMicrophone { _ in } },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                OnboardingPermissionRow(
                    title: "Speech Recognition",
                    detail: "On-device transcription when using Apple Speech.",
                    state: permissions.speechRecognition,
                    grant: { permissions.requestSpeechRecognition { _ in } },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                )
                OnboardingPermissionRow(
                    title: "Accessibility",
                    detail: "Focuses apps and pastes dictated text.",
                    state: permissions.accessibility,
                    grant: { permissions.openAccessibilitySettings() },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                OnboardingPermissionRow(
                    title: "Input Monitoring",
                    detail: "Detects your push-to-talk key globally.",
                    state: permissions.inputMonitoring,
                    grant: { permissions.requestInputMonitoring() },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                )
                ApplicationsLocationCard()
                RelaunchCard(reason: "After Accessibility or Input Monitoring, macOS may need Cadence to relaunch once.")
            }
        }
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionStatus
    let grant: () -> Void
    let settingsURL: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: glyph)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Text("Granted").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            } else if state == .denied || state == .restricted {
                Button("Settings") {
                    if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
            } else {
                Button("Grant") { grant() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    private var glyph: String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private var tint: Color {
        switch state {
        case .granted: return .green
        case .denied, .restricted: return .orange
        default: return Color.mello
        }
    }
}

/// Inline card that explains the "quit & reopen" requirement and offers a
/// single button to do it cleanly. Onboarding progress is preserved across
/// the relaunch via `UserPreferences.onboardingStep`.
private struct RelaunchCard: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(Color.mello)
                Text("Restart needed?")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(reason)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                AppRelocator.relaunchSelf()
            } label: {
                Label("Restart Cadence now", systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mello.opacity(0.08))
        )
    }
}

private struct PushToTalkKeyStep: View {
    @StateObject private var captureController = KeyCaptureController()
    @ObservedObject private var prefs = UserPreferences.shared
    let onContinue: () -> Void

    var body: some View {
        StepShell(
            title: "Choose your activation",
            subtitle: "Cadence can either record while you hold a key, or toggle on a quick double-tap. Pick whichever fits your hands.",
            primaryLabel: "Save",
            onPrimary: onContinue
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $prefs.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(prefs.activationMode.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Picker("Key", selection: $prefs.pushToTalkKey) {
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(label(for: key)).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)

                if prefs.pushToTalkKey == .custom {
                    HStack {
                        Text(captureController.capturedKeyDescription)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                        Button(captureController.isCapturing ? "Listening…" : "Set Key") {
                            captureController.start()
                        }
                        .disabled(captureController.isCapturing)
                    }
                    .onChange(of: captureController.capturedKeyCode) { _, code in
                        if let code { prefs.customKeyCode = code }
                    }
                }

                StepHint(text: "If another app already uses hold-to-talk on the same key (like Claude Desktop's voice mode), choose Double-tap to toggle.")
            }
        }
    }

    private func label(for key: PushToTalkKey) -> String {
        if key.isRecommended {
            return "\(key.displayName) — recommended"
        }
        return key.displayName
    }
}

private struct TestStep: View {
    @ObservedObject private var coordinator = DictationCoordinator.shared
    @ObservedObject private var prefs = UserPreferences.shared
    let onContinue: () -> Void

    var body: some View {
        StepShell(
            title: "Try it now",
            subtitle: "Hold your push-to-talk key and say: “Hey Claude, write a one-sentence test prompt.”",
            primaryLabel: "Continue",
            onPrimary: onContinue
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LiveStatusCard(stage: coordinator.stage, lastDestination: coordinator.lastDestinationName, lastFinal: coordinator.lastFinalText)
                StepHint(text: "Configured key: \(prefs.pushToTalkKey.displayName). You can change it any time in Settings.")
            }
        }
    }
}

private struct DoneStep: View {
    @ObservedObject private var prefs = UserPreferences.shared
    let onClose: () -> Void

    var body: some View {
        StepShell(
            title: "You're *ready*.",
            subtitle: "Hold your key anywhere on your Mac, say a destination like “Hey Claude,” then dictate naturally. The Cadence icon lives in your menu bar — click it for Settings, history, or to send feedback.",
            primaryLabel: "Start using Cadence",
            onPrimary: onClose
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { newValue in
                        prefs.launchAtLogin = newValue
                        LaunchAtLogin.setEnabled(newValue)
                    }
                ))
                Toggle("Show floating recording indicator", isOn: $prefs.showFloatingIndicator)
                Toggle("Save dictation history", isOn: $prefs.saveDictationHistory)
                Toggle("Reuse existing windows when possible", isOn: $prefs.preferExistingWindows)
                Toggle("Detect spoken destination phrases", isOn: $prefs.enableSpokenRouting)

                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Stuck on something? Email ")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    + Text("support@cadence.me")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mello)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Reusable bits

private struct StepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.mello.opacity(0.12))
                Text("\(number)").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.mello)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(description).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExampleBox: View {
    let raw: String
    let cleaned: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(label: "You say", text: raw, faded: true)
            row(label: "Cadence pastes", text: cleaned, faded: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func row(label: String, text: String, faded: Bool) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(faded ? .secondary : .primary)
        }
    }
}

private struct PermissionRow: View {
    let state: PermissionStatus
    let grantedText: String
    let deniedText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.15)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var glyph: String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .notDetermined, .unknown: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .granted: return .green
        case .denied, .restricted: return .orange
        case .notDetermined, .unknown: return Color.mello
        }
    }

    private var text: String {
        switch state {
        case .granted: return grantedText
        case .denied, .restricted: return deniedText
        case .notDetermined, .unknown: return pendingText
        }
    }
}

private struct StepHint: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Surfaced when the app is running from a non-/Applications path.
/// Without this, Accessibility / Input Monitoring permissions get
/// re-set on every rebuild because TCC keys to the binary signature.
private struct ApplicationsLocationCard: View {
    @State private var isInApps: Bool = AppRelocator.isInApplications

    var body: some View {
        if isInApps {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mello)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.mello.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install Cadence in /Applications")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Recommended for stable permissions. After moving, run Permission Repair once. Rebuilds with ad-hoc signing can still break grants — sign with a free Apple Development team in Xcode to fix that.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Move & Relaunch") {
                            _ = AppRelocator.moveToApplicationsAndRelaunch()
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.mello.opacity(0.08))
            )
        }
    }
}

private struct LiveStatusCard: View {
    let stage: DictationStage
    let lastDestination: String?
    let lastFinal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: glyph)
                    .foregroundStyle(color)
                Text(stage.userFacingDescription)
                    .font(.system(size: 13, weight: .semibold))
            }

            if let lastDestination {
                Text("Detected: \(lastDestination)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let lastFinal, !lastFinal.isEmpty {
                Text(lastFinal)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var glyph: String {
        switch stage {
        case .recording: return "mic.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "waveform"
        }
    }
    private var color: Color {
        switch stage {
        case .recording: return .red
        case .completed: return .green
        case .failed: return .orange
        default: return Color.mello
        }
    }
}
