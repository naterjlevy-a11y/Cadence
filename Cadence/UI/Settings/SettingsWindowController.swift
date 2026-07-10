import Foundation
import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cadence"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: CadenceSettingsRootView())
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        self.init(window: window)
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Present the window scrolled to a specific tab (e.g. "history", "general").
    func present(tabId: String) {
        SettingsNavigation.shared.selectedTabId = tabId
        present()
    }
}

/// Shared selection so other parts of the app (menu bar, notifications) can
/// open Settings already focused on a given tab.
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTabId: String = SettingsTab.account.rawValue
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case account
    case general
    case dictation
    case routingDestinations
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .general: return "General"
        case .dictation: return "Dictation"
        case .routingDestinations: return "Routing & Destinations"
        case .history: return "History"
        }
    }

    var glyph: String {
        switch self {
        case .account: return "person.crop.circle.fill"
        case .general: return "gearshape.fill"
        case .dictation: return "waveform"
        case .routingDestinations: return "arrow.triangle.branch"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .account: return "Profile, plan, and subscription"
        case .general: return "Hotkey, appearance, popup, permissions"
        case .dictation: return "Engine, cleanup, dictionary"
        case .routingDestinations: return "Spoken routing and per-app destinations"
        case .history: return "Past dictations"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject private var nav = SettingsNavigation.shared

    private var selection: SettingsTab {
        SettingsTab(rawValue: nav.selectedTabId) ?? .account
    }

    private func select(_ tab: SettingsTab) {
        nav.selectedTabId = tab.rawValue
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
            Divider().opacity(0.4)
            ScrollView(.vertical, showsIndicators: false) {
                detail
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
        .cadenceThemed()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 30, cornerRadius: 7)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Cadence")
                        .font(.melloDisplay(18))
                        .tracking(-0.2)
                    Text("Voice routing")
                        .font(.melloMono(9.5, weight: .medium))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarRow(tab: tab, isSelected: selection == tab) {
                        select(tab)
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("v0.1 · MVP build")
                    .font(.melloMono(9.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("Hold a key. Say where. Speak.")
                    .font(.melloBody(10.5))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.title)
                    .font(.melloDisplay(30))
                    .tracking(-0.3)
                Text(selection.subtitle)
                    .font(.melloBody(13))
                    .foregroundStyle(.secondary)
            }

            switch selection {
            case .account: AccountSettingsView()
            case .general: GeneralSettingsView()
            case .dictation: DictationSettingsView()
            case .routingDestinations: RoutingDestinationsSettingsView()
            case .history: HistorySettingsView()
            }
        }
        .frame(maxWidth: 640, alignment: .topLeading)
    }
}

private struct SidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.glyph)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? Color.white : Color.mello)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.mello : Color.mello.opacity(0.12))
                    )
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : (hovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Section primitives

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.melloMono(10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let subtitle {
                    Text(subtitle)
                        .font(.melloBody(12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: () -> Content

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

// MARK: - General

private struct PopupSettingsSection: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var chromeProfiles: [String] = ChromeCookieImporter.availableChromeProfiles()
    @State private var syncToast: String?

    var body: some View {
        SettingsCard(
            "Popup window",
            subtitle: "Small, top-right, always on top. When Chrome session sync is on, Cadence copies your sign-in cookies from Chrome before each popup loads."
        ) {
            SettingsRow(
                "Use my Chrome session",
                detail: "Reads cookies from your local Chrome profile. macOS asks once to access Chrome Safe Storage in Keychain — choose Always Allow."
            ) {
                Toggle("", isOn: $prefs.importChromeCookies).labelsHidden()
            }

            if prefs.importChromeCookies {
                SettingsRow("Chrome profile") {
                    Picker("", selection: $prefs.chromeCookieProfile) {
                        ForEach(chromeProfiles, id: \.self) { profile in
                            Text(profile).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    .onAppear { chromeProfiles = ChromeCookieImporter.availableChromeProfiles() }
                }

                SettingsRow("Sync cookies now", detail: syncToast) {
                    Button("Sync now") {
                        let message = ChromeCookieImporter.shared.refreshAll()
                        syncToast = message
                    }
                }
            }

            SettingsRow(
                "Open in real Chrome window instead",
                detail: "Chromeless --app= window with your full browser session. Can't stay always-on-top. Set the default browser under Routing & Destinations."
            ) {
                Toggle("", isOn: $prefs.popupUsesBrowserAppWindow).labelsHidden()
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @StateObject private var capture = KeyCaptureController()
    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard("Appearance") {
                SettingsRow("Show menu bar icon") { Toggle("", isOn: $prefs.showMenuBarIcon).labelsHidden() }
                SettingsRow("Show floating recording indicator") { Toggle("", isOn: $prefs.showFloatingIndicator).labelsHidden() }
                SettingsRow("Play sounds", detail: "Wispr-style chime on start and send.") {
                    Toggle("", isOn: $prefs.playSounds).labelsHidden()
                }
                if prefs.playSounds {
                    SettingsRow("Sound volume") {
                        Slider(value: $prefs.soundVolume, in: 0.05...1.0)
                            .frame(maxWidth: 180)
                    }
                }
            }
            SettingsCard("Startup") {
                SettingsRow("Launch at login") {
                    Toggle("", isOn: Binding(
                        get: { prefs.launchAtLogin },
                        set: { newValue in
                            prefs.launchAtLogin = newValue
                            LaunchAtLogin.setEnabled(newValue)
                        }
                    )).labelsHidden()
                }
            }
            SettingsCard("Activation mode", subtitle: prefs.activationMode.description) {
                SettingsRow("Pause voice routing", detail: prefs.paused ? "Cadence is paused — push-to-talk is ignored." : "Push-to-talk is active.") {
                    Toggle("", isOn: $prefs.paused).labelsHidden()
                }
                Picker("", selection: $prefs.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if prefs.activationMode == .doubleTapToggle || prefs.activationMode == .hybrid {
                    SettingsRow("Max gap between taps", detail: "How fast you have to double-tap. Wispr Flow uses ~450 ms.") {
                        Stepper(value: $prefs.doubleTapMaxIntervalMs, in: 200...700, step: 20) {
                            Text("\(prefs.doubleTapMaxIntervalMs) ms").monospacedDigit()
                        }
                    }
                }
            }
            SettingsCard("Activation key") {
                SettingsRow("Key") {
                    Picker("", selection: $prefs.pushToTalkKey) {
                        ForEach(PushToTalkKey.allCases) { key in
                            Text(key.displayName + (key.isRecommended ? " · recommended" : "")).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
                if prefs.pushToTalkKey == .custom {
                    SettingsRow("Custom keycode", detail: "Captured: \(prefs.customKeyCode)") {
                        HStack {
                            Text(capture.capturedKeyDescription)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button(capture.isCapturing ? "Listening…" : "Capture") { capture.start() }
                                .disabled(capture.isCapturing)
                        }
                        .onChange(of: capture.capturedKeyCode) { _, code in
                            if let code { prefs.customKeyCode = code }
                        }
                    }
                }
            }
            SettingsCard("Timing") {
                SettingsRow("Minimum hold", detail: "Tap-and-release shorter than this is ignored.") {
                    Stepper(value: $prefs.minimumHoldMilliseconds, in: 100...2000, step: 50) {
                        Text("\(prefs.minimumHoldMilliseconds) ms").monospacedDigit()
                    }
                }
            }
            PopupSettingsSection()
            GeneralPrivacySection()
            HelpFeedbackSection()
            #if DEBUG
            SettingsCard("Developer") {
                SettingsRow("Verbose debug logging", detail: "Includes redacted text in os_log.") {
                    Toggle("", isOn: $prefs.developerDebugMode).labelsHidden()
                }
                SettingsRow("Sentry test event", detail: "Sends a harmless message to your Sentry project.") {
                    Button("Send test") {
                        CrashReporter.captureMessage("Cadence manual test event from Settings")
                    }
                    .disabled(!CrashReporter.isEnabled)
                }
                SettingsRow("Reset onboarding", detail: "Show the welcome flow again on next launch.") {
                    Button("Reset") { prefs.hasCompletedOnboarding = false }
                }
            }
            #endif

            HStack {
                Spacer()
                Button("Reset all settings…", role: .destructive) {
                    showResetConfirm = true
                }
            }
            .confirmationDialog(
                "Reset all settings?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset everything", role: .destructive) {
                    prefs.resetAllToDefaults()
                    DictationCoordinator.shared.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restores Cadence to factory defaults. Your Groq key in Keychain or ~/.config/cadence/.env is not removed.")
            }
        }
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

// MARK: - Dictation

private struct DictationSettingsView: View {
    @ObservedObject private var prefs = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TranscriptionSettingsSection()

            SettingsCard("Cleanup level", subtitle: prefs.cleanupLevel.description) {
                Picker("", selection: $prefs.cleanupLevel) {
                    ForEach(CleanupLevel.allCases) { level in Text(level.displayName).tag(level) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsCard("Recording limits") {
                SettingsRow("Maximum recording", detail: "Auto-stops at this length.") {
                    Stepper(value: $prefs.maximumRecordingSeconds, in: 30...600, step: 15) {
                        Text("\(prefs.maximumRecordingSeconds) s").monospacedDigit()
                    }
                }
            }

            SettingsCard("Cleanup options") {
                SettingsRow("Remove filler words", detail: "Drops \"um\", \"uh\", \"you know\".") {
                    Toggle("", isOn: $prefs.removeFillerWords).labelsHidden()
                }
                SettingsRow("Add punctuation") { Toggle("", isOn: $prefs.addPunctuation).labelsHidden() }
                SettingsRow("Auto-format spoken lists", detail: "Turns \"first… second… third…\" into numbered lists.") {
                    Toggle("", isOn: $prefs.autoFormatLists).labelsHidden()
                }
                SettingsRow("Auto-capitalize known brand names", detail: "Wispr Flow, ChatGPT, Cursor, macOS, Xcode, Tailwind, etc.") {
                    Toggle("", isOn: $prefs.brandDictionaryEnabled).labelsHidden()
                }
                SettingsRow("Smart formatting", detail: "Lowercase \"i\" → \"I\", common contractions, smart quotes, em dashes. Never removes words.") {
                    Toggle("", isOn: $prefs.smartFormattingEnabled).labelsHidden()
                }
            }

            SettingsCard(
                "Personal dictionary",
                subtitle: "Add names, brands, or jargon that get misheard. Cadence keeps these spelled exactly the way you type them."
            ) {
                PersonalDictionaryEditor()
            }

        }
    }
}

private struct PersonalDictionaryEditor: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var newTerm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Add a word or phrase", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if prefs.personalDictionary.isEmpty {
                Text("No custom words yet. Try adding your name, a company, or a product Cadence keeps mishearing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                FlowChips(items: prefs.personalDictionary) { term in
                    removeTerm(term)
                }
            }
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var terms = prefs.personalDictionary
        if !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            terms.append(trimmed)
            prefs.personalDictionary = terms
        }
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        prefs.personalDictionary.removeAll { $0 == term }
    }
}

/// A simple wrapping row of removable chips.
struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlexibleWrap(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.mello.opacity(0.12))
                )
                .overlay(
                    Capsule().strokeBorder(Color.mello.opacity(0.25), lineWidth: 0.6)
                )
            }
        }
    }
}

/// Lightweight flow layout that wraps its children onto multiple lines.
struct FlexibleWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Routing & Destinations

private struct RoutingDestinationsSettingsView: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var destinations: [Destination] = DestinationRegistry.shared.destinations
    @State private var selectionId: Destination.ID? = DestinationRegistry.shared.destinations.first?.id

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoutingExplainerCard()

            SettingsCard("Routing") {
                SettingsRow(
                    "Detect spoken destination phrases",
                    detail: "Turn off to always type into the app you're in, no matter what you say."
                ) {
                    Toggle("", isOn: $prefs.enableSpokenRouting).labelsHidden()
                }
                SettingsRow("If you don't name a destination") {
                    Picker("", selection: $prefs.noRoutePolicy) {
                        ForEach(NoRoutePolicy.allCases) { p in Text(p.displayName).tag(p) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            AddDestinationCard(onAdded: { newId in
                refresh()
                selectionId = newId
            })

            QuickPasteCard(onAdded: { newId in
                refresh()
                selectionId = newId
            })

            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR DESTINATIONS")
                    .font(.melloMono(10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("Pick one to rename it, add nicknames, or change how it opens.")
                    .font(.melloBody(12.5))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(destinations) { dest in
                            DestinationListRow(
                                destination: dest,
                                isSelected: selectionId == dest.id,
                                onSelect: { selectionId = dest.id }
                            )
                        }
                    }
                    .frame(width: 200)

                    if let id = selectionId,
                       let dest = destinations.first(where: { $0.id == id }) {
                        DestinationDetailView(destination: dest, onSave: refresh)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text("Select a destination")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DisclosureGroup("Advanced routing options") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCard("Window behavior") {
                        SettingsRow("Reuse existing windows when possible") {
                            Toggle("", isOn: $prefs.preferExistingWindows).labelsHidden()
                        }
                        SettingsRow("Default browser") {
                            Picker("", selection: $prefs.browserPreference) {
                                ForEach(BrowserPreference.allCases) { b in Text(b.displayName).tag(b) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                    }
                    SettingsCard("Submission") {
                        SettingsRow("Auto-submit after paste", detail: "Per-destination override applies.") {
                            Toggle("", isOn: $prefs.autoSubmit).labelsHidden()
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.top, 4)
        }
        .frame(minHeight: 460, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .preferencesDidChange)) { _ in refresh() }
    }

    private func refresh() {
        destinations = DestinationRegistry.shared.destinations
    }
}

private struct RoutingExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.mello)
                Text("How routing works")
                    .font(.melloBody(14, weight: .semibold))
            }
            Text("Start talking with \u{201C}Hey\u{201D} and a name to send your words somewhere specific. Without a greeting, Cadence just types into the app you're already in.")
                .font(.melloBody(12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ExampleRow(phrase: "\u{201C}Hey Claude, summarize this email\u{201D}", result: "Opens Claude, pastes your words")
                ExampleRow(phrase: "\u{201C}Hey Inbox, reply to Sarah\u{201D}", result: "Goes to a website you added below")
                ExampleRow(phrase: "\u{201C}Hey email\u{201D}", result: "Pastes a saved snippet (Quick paste)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.mello.opacity(0.07))
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private struct ExampleRow: View {
        let phrase: String
        let result: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(phrase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(result)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct AddDestinationCard: View {
    let onAdded: (Destination.ID) -> Void

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var openInPopup: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard(
            "Add a website",
            subtitle: "Give a website a nickname you can say. Then \u{201C}Hey [nickname]\u{201D} opens it and drops your dictation in."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. What do you want to say?")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Nickname, e.g. Inbox", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Which website should it open?")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("https://mail.google.com", text: $url)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(isOn: $openInPopup) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Open in a floating mini-window")
                            .font(.system(size: 12))
                        Text("Stays on top instead of switching apps. Turn off to open a normal browser tab.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Add website") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        normalizedURL() != nil
    }

    private func normalizedURL() -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            withScheme = "https://\(trimmed)"
        } else {
            return nil
        }
        return URL(string: withScheme)
    }

    private func add() {
        guard let resolved = normalizedURL() else {
            errorMessage = "Enter a valid web address like https://example.com"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        CustomDestinationsStore.shared.add(
            name: trimmedName,
            url: resolved,
            openInPopup: openInPopup
        )
        let newId = "user:" + trimmedName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        errorMessage = nil
        name = ""
        url = ""
        onAdded(newId)
    }
}

private struct QuickPasteCard: View {
    let onAdded: (Destination.ID) -> Void

    @State private var keyword: String = ""
    @State private var value: String = ""
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard(
            "Quick paste (keyword)",
            subtitle: "Save text you type a lot. Saying \u{201C}Hey [keyword]\u{201D} instantly pastes it wherever your cursor is \u{2014} no app switching."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyword to say")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("e.g. email, address, signature", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Text to paste")
                        .font(.system(size: 12, weight: .semibold))
                    TextEditor(text: $value)
                        .font(.system(size: 12.5))
                        .frame(minHeight: 56)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                }

                Label("Stored only on this Mac in plain text. Avoid using it for sensitive passwords.", systemImage: "lock.open")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Save keyword") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty &&
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        guard isValid else {
            errorMessage = "Enter a keyword and the text to paste."
            return
        }
        CustomDestinationsStore.shared.addSnippet(keyword: trimmedKeyword, snippet: value)
        let newId = "snippet:" + trimmedKeyword.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        errorMessage = nil
        keyword = ""
        value = ""
        onAdded(newId)
    }
}

private struct DestinationListRow: View {
    let destination: Destination
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(destination.enabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                if destination.isSnippet {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mello)
                }
                Text(destination.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if !destination.subdestinations.isEmpty {
                    Text("\(destination.subdestinations.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.mello.opacity(0.15))
                        )
                        .foregroundStyle(Color.mello)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.07) : (hovering ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DestinationDetailView: View {
    let destination: Destination
    let onSave: () -> Void

    @State private var enabled: Bool
    @State private var aliasesText: String
    @State private var preferredMode: LaunchMode
    @State private var autoSubmit: Bool
    @State private var pasteDelay: Double
    @State private var subdestinations: [Subdestination]
    @State private var openInPopup: Bool
    @State private var snippetText: String

    init(destination: Destination, onSave: @escaping () -> Void) {
        self.destination = destination
        self.onSave = onSave
        _enabled = State(initialValue: destination.enabled)
        _aliasesText = State(initialValue: destination.customUserAliases.joined(separator: "\n"))
        _preferredMode = State(initialValue: destination.preferredMode)
        _autoSubmit = State(initialValue: destination.autoSubmitEnabled)
        _pasteDelay = State(initialValue: destination.pasteDelaySeconds)
        _subdestinations = State(initialValue: destination.subdestinations)
        _openInPopup = State(initialValue: destination.openInPopup)
        _snippetText = State(initialValue: destination.pasteSnippet ?? "")
    }

    private var isUserDestination: Bool { destination.id.hasPrefix("user:") }
    private var isSnippetDestination: Bool { destination.id.hasPrefix("snippet:") || destination.isSnippet }
    private var supportsPopup: Bool { destination.url != nil }

    var body: some View {
        if isSnippetDestination {
            snippetBody
        } else {
            standardBody
        }
    }

    private var snippetBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                "Quick paste: \u{201C}Hey \(destination.displayName)\u{201D}",
                subtitle: "Saying this keyword pastes the text below into the current app."
            ) {
                SettingsRow("Enabled") { Toggle("", isOn: $enabled).labelsHidden() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text to paste").font(.system(size: 12, weight: .semibold))
                    TextEditor(text: $snippetText)
                        .font(.system(size: 12.5))
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
            }

            SettingsCard("Other keywords", subtitle: "One per line. Any of these will paste the same text.") {
                TextEditor(text: $aliasesText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
            }

            HStack {
                Button(role: .destructive) {
                    CustomDestinationsStore.shared.remove(id: destination.id)
                    DestinationRegistry.shared.clearOverride(for: destination.id)
                    onSave()
                } label: {
                    Label("Delete keyword", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                Spacer()
                Button("Save changes") { saveSnippet() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func saveSnippet() {
        let aliases = aliasesText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let override = DestinationOverride(
            enabled: enabled,
            customUserAliases: aliases,
            pasteSnippet: snippetText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        DestinationRegistry.shared.updateOverride(override, for: destination.id)
        onSave()
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(destination.displayName) {
                SettingsRow("Enabled") { Toggle("", isOn: $enabled).labelsHidden() }
                SettingsRow("Open as") {
                    Picker("", selection: $preferredMode) {
                        Text("Native preferred").tag(LaunchMode.nativeAppPreferred)
                        Text("Website preferred").tag(LaunchMode.websitePreferred)
                        Text("Native only").tag(LaunchMode.nativeAppOnly)
                        Text("Website only").tag(LaunchMode.websiteOnly)
                        Text("Stay in current app").tag(LaunchMode.currentApp)
                    }.labelsHidden().frame(maxWidth: 200)
                }
                if supportsPopup {
                    SettingsRow(
                        "Open in popup",
                        detail: "Show this destination in Cadence's floating mini-browser instead of switching apps."
                    ) {
                        Toggle("", isOn: $openInPopup).labelsHidden()
                    }
                }
                SettingsRow("Auto-submit after paste") { Toggle("", isOn: $autoSubmit).labelsHidden() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Paste delay").font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.2fs", pasteDelay))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $pasteDelay, in: 0.05...2.0)
                }
            }

            SettingsCard("Built-in aliases") {
                Text(destination.aliases.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard("Custom aliases", subtitle: "One per line. Spoken at the start, e.g. \"Hey [alias], …\".") {
                TextEditor(text: $aliasesText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
            }

            SettingsCard(
                "Document shortcuts",
                subtitle: "Add specific URLs you can target by name. Say \"Hey \(destination.displayName), [shortcut name], …\" and Cadence opens that URL instead."
            ) {
                ForEach($subdestinations) { $sub in
                    SubdestinationEditor(sub: $sub) {
                        subdestinations.removeAll { $0.id == sub.id }
                    }
                }
                Button {
                    subdestinations.append(
                        Subdestination(name: "", aliases: [], url: URL(string: "https://")!)
                    )
                } label: {
                    Label("Add shortcut", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.mello)
            }

            HStack {
                if isUserDestination {
                    Button(role: .destructive) {
                        CustomDestinationsStore.shared.remove(id: destination.id)
                        DestinationRegistry.shared.clearOverride(for: destination.id)
                        onSave()
                    } label: {
                        Label("Delete destination", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Reset to defaults") {
                    DestinationRegistry.shared.clearOverride(for: destination.id)
                    onSave()
                }
                Button("Save changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func save() {
        let aliases = aliasesText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let validSubs = subdestinations
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let override = DestinationOverride(
            enabled: enabled,
            customUserAliases: aliases,
            preferredMode: preferredMode,
            autoSubmitEnabled: autoSubmit,
            pasteDelaySeconds: pasteDelay,
            subdestinations: validSubs,
            openInPopup: openInPopup
        )
        DestinationRegistry.shared.updateOverride(override, for: destination.id)
        onSave()
    }
}

private struct SubdestinationEditor: View {
    @Binding var sub: Subdestination
    let onDelete: () -> Void

    @State private var aliasesText: String
    @State private var urlText: String

    init(sub: Binding<Subdestination>, onDelete: @escaping () -> Void) {
        self._sub = sub
        self.onDelete = onDelete
        _aliasesText = State(initialValue: sub.wrappedValue.aliases.joined(separator: ", "))
        _urlText = State(initialValue: sub.wrappedValue.url.absoluteString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name (e.g. Capstone, Nate Levy)", text: $sub.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            TextField("URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .onChange(of: urlText) { _, newValue in
                    if let url = URL(string: newValue) { sub.url = url }
                }
            TextField("Aliases (comma separated)", text: $aliasesText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .onChange(of: aliasesText) { _, newValue in
                    sub.aliases = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Account

private struct AccountSettingsView: View {
    @ObservedObject private var billing = BillingService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AccountSettingsSection()
            SubscriptionSettingsSection()
        }
        .sheet(isPresented: $billing.showEmbeddedCheckout) {
            EmbeddedCheckoutSheet()
        }
    }
}

// MARK: - History

private struct HistorySettingsView: View {
    var body: some View {
        HistoryView(embedded: true)
    }
}

// MARK: - General privacy (folded from Privacy & Permissions)

private struct GeneralPrivacySection: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var duplicates: [URL] = []
    @State private var repairBanner: String?

    var body: some View {
        Group {
            SettingsCard("Data") {
                SettingsRow("Save dictation history", detail: "View past dictations in the History tab.") {
                    Toggle("", isOn: $prefs.saveDictationHistory).labelsHidden()
                }
                SettingsRow("Preserve clipboard before paste") { Toggle("", isOn: $prefs.preserveClipboard).labelsHidden() }
            }
            SettingsCard("On-device transcription") {
                SettingsRow(
                    "Prefer on-device when using Apple Speech",
                    detail: "More private, slightly worse on long monologues. Only used if engine is set to Apple Speech (Dictation tab)."
                ) {
                    Toggle("", isOn: $prefs.preferOnDeviceTranscription).labelsHidden()
                }
            }
            SettingsCard("About") {
                Text("Cadence transcribes speech using Groq Whisper (cloud) or Apple Speech (on-device). Audio is only sent while the activation key is engaged.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            SettingsCard(
                "macOS permissions",
                subtitle: "If a toggle looks ON in System Settings but Cadence still says denied, use Repair below — it clears the stale entry so the next prompt registers this build."
            ) {
                PermissionRowsView()
                if !permissions.missingPermissions.isEmpty {
                    Divider().opacity(0.4)
                    Button {
                        permissions.resetAllAndReprompt()
                    } label: {
                        Label("Reset all & re-prompt", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let banner = repairBanner {
                    Text(banner)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !duplicates.isEmpty {
                SettingsCard(
                    "Other copies on disk",
                    subtitle: "Extra copies of Cadence confuse macOS permissions. Move them to the Trash."
                ) {
                    ForEach(duplicates, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: "app.dashed").foregroundStyle(.secondary)
                            Text(url.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                    }
                    Button {
                        let count = AppRelocator.trashDuplicates(duplicates)
                        duplicates = AppRelocator.duplicateInstallations()
                        repairBanner = "Moved \(count) duplicate\(count == 1 ? "" : "s") to the Trash."
                    } label: {
                        Label("Move all duplicates to Trash", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Spacer()
                Button("Refresh status") { permissions.refreshAll() }
            }
        }
        .onAppear { duplicates = AppRelocator.duplicateInstallations() }
    }
}

private struct HelpFeedbackSection: View {
    var body: some View {
        SettingsCard("Help & feedback") {
            HStack(spacing: 8) {
                Button {
                    UpdaterService.shared.checkForUpdates(nil)
                } label: {
                    Label("Check for updates", systemImage: "arrow.down.circle")
                }
                Button {
                    sendFeedback()
                } label: {
                    Label("Send feedback", systemImage: "envelope")
                }
                Spacer()
            }
        }
    }

    private func sendFeedback() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let subject = "Cadence \(version) (\(build)) feedback"
        let body = "\n\n—\nApp: Cadence \(version) (\(build))\nmacOS: \(os)\n"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:support@cadence.me?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRowsView: View {
    @ObservedObject private var permissions = PermissionsManager.shared

    var body: some View {
        permissionRow(
            name: "Microphone",
            state: permissions.microphone,
            description: "Records your voice while the activation key is engaged.",
            request: { permissions.requestMicrophone { _ in } },
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        permissionRow(
            name: "Speech Recognition",
            state: permissions.speechRecognition,
            description: "Transcribes audio on-device.",
            request: { permissions.requestSpeechRecognition { _ in } },
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        )
        permissionRow(
            name: "Accessibility",
            state: permissions.accessibility,
            description: "Focuses apps and pastes dictated text.",
            request: { permissions.openAccessibilitySettings() },
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        permissionRow(
            name: "Input Monitoring",
            state: permissions.inputMonitoring,
            description: "Detects your activation key globally.",
            request: { permissions.requestInputMonitoring() },
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    @ViewBuilder
    private func permissionRow(
        name: String,
        state: PermissionStatus,
        description: String,
        request: @escaping () -> Void,
        settingsURL: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph(for: state))
                .foregroundStyle(color(for: state))
                .frame(width: 18)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Text("Granted").foregroundStyle(.green).font(.system(size: 12, weight: .semibold))
            case .denied, .restricted:
                Button("Open Settings") {
                    if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
                }
            case .notDetermined, .unknown:
                Button("Grant") { request() }
            }
        }
    }

    private func glyph(for state: PermissionStatus) -> String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .notDetermined, .unknown: return "circle"
        }
    }

    private func color(for state: PermissionStatus) -> Color {
        switch state {
        case .granted: return .green
        case .denied, .restricted: return .orange
        case .notDetermined, .unknown: return .secondary
        }
    }
}

// MARK: - Account (Cadence Cloud)

private struct AccountSettingsSection: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var showSignIn = false

    private var accountStatusText: String {
        if !auth.isSignedIn { return "Not signed in" }
        if auth.isAnonymous { return "Guest session" }
        return auth.userEmail ?? "Signed in"
    }

    var body: some View {
        if CloudConfig.shared.isCloudEnabled {
            SettingsCard(
                "Cadence Cloud",
                subtitle: "Included Groq transcription for new users (~3 hours/month free). No Groq account required."
            ) {
                SettingsRow("Account") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(accountStatusText)
                            .foregroundStyle(auth.isSignedIn && !auth.isAnonymous ? .green : .secondary)
                        if auth.isSignedIn {
                            Text("Plan: \(auth.plan)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if auth.isSignedIn && !auth.isAnonymous {
                        Button("Sign out") { auth.signOut() }
                    } else {
                        Button(auth.isAnonymous ? "Sign in or create account" : "Sign in") {
                            showSignIn = true
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                    if auth.isSignedIn && auth.isAnonymous {
                        Button("Sign out") { auth.signOut() }
                    }
                }

                if auth.isAnonymous && auth.isSignedIn {
                    Text("You’re on a guest session. Sign in to save your account and recover cloud usage across devices.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = auth.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInView(onClose: { showSignIn = false })
            }
        } else {
            SettingsCard(
                "Cadence Cloud",
                subtitle: "Not configured yet. Copy CloudConfig.example.plist → CloudConfig.plist and fill in Supabase + API URLs. See DEPLOY.md."
            ) {
                Text("Ship builds include CloudConfig.plist with your project keys (never commit real secrets to git).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Subscription (Cadence Pro)

private struct SubscriptionSettingsSection: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var billing = BillingService.shared

    private var isCheckoutLoading: Bool {
        if case .loading = billing.phase { return true }
        return false
    }

    var body: some View {
        if CloudConfig.shared.isCloudEnabled {
            SettingsCard(
                "Cadence Pro",
                subtitle: "Unlimited dictation, priority transcription, and AI cleanup on every paste — \(billing.priceDisplay)/\(billing.pricePeriod)."
            ) {
                if auth.plan == "pro" {
                    SettingsRow("Status") {
                        Text("Active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    HStack {
                        Button("Manage subscription") { billing.openManageSubscription() }
                        Spacer()
                    }
                } else {
                    HStack {
                        Button("Upgrade to Pro") {
                            billing.startUpgrade()
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isCheckoutLoading)
                        Spacer()
                    }
                }

                if isCheckoutLoading {
                    ProgressView("Loading checkout…")
                        .font(.system(size: 11))
                }

                if case let .failed(message) = billing.phase {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Transcription (Dictation tab)

private struct TranscriptionSettingsSection: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @ObservedObject private var coordinator = DictationCoordinator.shared

    var body: some View {
        SettingsCard(
            "Transcription",
            subtitle: "Speech-to-text is powered by Cadence Cloud (Groq Whisper) — no setup or API key needed."
        ) {
            SettingsRow(
                "Use on-device transcription instead",
                detail: "Apple Speech runs fully offline. More private, but less accurate on names and proper nouns."
            ) {
                Toggle("", isOn: Binding(
                    get: { prefs.transcriptionProvider == "apple" },
                    set: { prefs.transcriptionProvider = $0 ? "apple" : "groq" }
                )).labelsHidden()
            }

            if let last = coordinator.lastTranscriptionProvider {
                SettingsRow(
                    "Last dictation used",
                    detail: last == "AppleSpeech" && prefs.transcriptionProvider != "apple"
                        ? "Fell back to Apple Speech — check your connection."
                        : nil
                ) {
                    Text(friendlyProvider(last))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func friendlyProvider(_ raw: String) -> String {
        switch raw {
        case "CadenceCloud": return "Cadence Cloud"
        case "GroqWhisper":    return "Groq Whisper"
        case "AppleSpeech":    return "Apple Speech"
        default:                return raw
        }
    }
}

// MARK: - Visual effect background

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
