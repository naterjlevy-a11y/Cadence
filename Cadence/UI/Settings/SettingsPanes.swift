import SwiftUI
import AppKit

// MARK: - Root

/// Cadence settings v2 — Wispr-style. Sidebar of five panes; every pane is
/// clean rows (label left, control right). No explainer walls, no wizards.
struct CadenceSettingsRootView: View {
    @State private var tab: Pane = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, dictation, destinations, history, account
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .dictation: return "Dictation"
            case .destinations: return "Destinations"
            case .history: return "History"
            case .account: return "Account"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .dictation: return "waveform"
            case .destinations: return "arrow.triangle.branch"
            case .history: return "clock"
            case .account: return "person.crop.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.strokeHairline)
            detail
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color.melloInk)
        .cadenceThemed()
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                PillMark().frame(width: 34)
                Text("Cadence")
                    .font(.cadTitle(16))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(Pane.allCases) { pane in
                CSidebarItem(icon: pane.icon, title: pane.title, selected: tab == pane) {
                    tab = pane
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 190)
        .background(Color.melloMidnight.opacity(0.6))
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tab.title)
                    .font(.cadTitle(21))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.bottom, 2)

                switch tab {
                case .general: GeneralPane()
                case .dictation: DictationPane()
                case .destinations: DestinationsPane()
                case .history: HistoryPane()
                case .account: AccountPane()
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @ObservedObject private var perms = PermissionsManager.shared

    var body: some View {
        content
            .onAppear { perms.refreshAll(); perms.startPolling() }
            .onDisappear { perms.stopPolling() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            CCard {
                CRow(title: "Launch at login") {
                    Toggle("", isOn: $prefs.launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: prefs.launchAtLogin) { _, v in LaunchAtLogin.apply(v) }
                }
                CDivider()
                CRow(title: "Show menu bar icon") {
                    Toggle("", isOn: $prefs.showMenuBarIcon).toggleStyle(.switch).labelsHidden()
                }
                CDivider()
                CRow(title: "Floating recording pill", subtitle: "The indicator that appears while you talk") {
                    Toggle("", isOn: $prefs.showFloatingIndicator).toggleStyle(.switch).labelsHidden()
                }
            }

            CSection("Sound")
            CCard {
                CRow(title: "Sounds") {
                    Toggle("", isOn: $prefs.playSounds).toggleStyle(.switch).labelsHidden()
                }
                if prefs.playSounds {
                    CDivider()
                    CRow(title: "Volume") {
                        Slider(value: $prefs.soundVolume, in: 0...1).frame(width: 140)
                    }
                }
            }

            CSection("Permissions")
            CCard {
                permissionRow("Microphone", perms.microphone,
                              action: { perms.requestMicrophone { _ in } })
                CDivider()
                permissionRow("Accessibility", perms.accessibility,
                              opensSettings: true, action: { perms.openAccessibilitySettings() })
            }

            HStack {
                Text("Cadence \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.cadBody(11))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Button("Send feedback") {
                    NSWorkspace.shared.open(URL(string: "mailto:support@cadenceapp.co")!)
                }
                .buttonStyle(.link)
                .font(.cadBody(11))
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, _ status: PermissionStatus,
                               opensSettings: Bool = false,
                               action: @escaping () -> Void) -> some View {
        CRow(title: name) {
            HStack(spacing: 8) {
                CStatusDot(ok: status == .granted)
                if status == .granted {
                    Text("On")
                        .font(.cadMedium(11.5))
                        .foregroundStyle(.green)
                } else {
                    Button(opensSettings ? "Open Settings" : "Allow", action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Dictation

struct DictationPane: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CCard {
                CRow(title: "Push-to-talk key") {
                    Picker("", selection: $prefs.pushToTalkKey) {
                        ForEach(PushToTalkKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                CDivider()
                CRow(title: "Activation", subtitle: nil) {
                    Picker("", selection: $prefs.activationMode) {
                        ForEach(ActivationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            CSection("Transcription")
            CCard {
                CRow(title: "Mode", subtitle: prefs.preferOnDeviceTranscription
                        ? "Nothing leaves your Mac"
                        : "Fast cloud transcription, audio deleted instantly") {
                    Picker("", selection: $prefs.preferOnDeviceTranscription) {
                        Text("Cloud · fast").tag(false)
                        Text("On-device · private").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                    .onChange(of: prefs.preferOnDeviceTranscription) { _, onDevice in
                        if onDevice { PermissionsManager.shared.requestSpeechRecognition { _ in } }
                    }
                }
                CDivider()
                CRow(title: "Max recording length") {
                    Picker("", selection: $prefs.maximumRecordingSeconds) {
                        Text("1 min").tag(60)
                        Text("5 min").tag(300)
                        Text("10 min").tag(600)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            CSection("Cleanup")
            CCard {
                CRow(title: "Level") {
                    Picker("", selection: $prefs.cleanupLevel) {
                        ForEach(CleanupLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                CDivider()
                CRow(title: "Remove filler words", subtitle: "\u{201C}um\u{201D}, \u{201C}uh\u{201D}, \u{201C}like\u{201D}") {
                    Toggle("", isOn: $prefs.removeFillerWords).toggleStyle(.switch).labelsHidden()
                }
                CDivider()
                CRow(title: "Add punctuation") {
                    Toggle("", isOn: $prefs.addPunctuation).toggleStyle(.switch).labelsHidden()
                }
                CDivider()
                CRow(title: "Format lists automatically") {
                    Toggle("", isOn: $prefs.autoFormatLists).toggleStyle(.switch).labelsHidden()
                }
            }

            CSection("Personal dictionary")
            CCard {
                VStack(alignment: .leading, spacing: 10) {
                    if prefs.personalDictionary.isEmpty {
                        Text("Names and terms Cadence should always spell right.")
                            .font(.cadBody(12))
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        FlowChips(items: prefs.personalDictionary) { term in
                            prefs.personalDictionary.removeAll { $0 == term }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Add a word…", text: $newTerm)
                            .textFieldStyle(.roundedBorder)
                            .font(.cadBody(12))
                            .frame(width: 200)
                            .onSubmit(addTerm)
                        Button("Add", action: addTerm)
                            .controlSize(.small)
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
            }
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !prefs.personalDictionary.contains(term) else { return }
        prefs.personalDictionary.append(term)
        newTerm = ""
    }
}

// MARK: - Destinations

struct DestinationsPane: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var destinations: [Destination] = DestinationRegistry.shared.destinations
    @State private var showAddWebsite = false
    @State private var showAddSnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CCard {
                CRow(title: "Spoken routing", subtitle: "\u{201C}Hey Claude, \u{2026}\u{201D} sends your words there") {
                    HStack(spacing: 8) {
                        CInfoHint(text: "Start with \u{201C}Hey\u{201D} and a destination name to send your words somewhere specific. Without a greeting, Cadence types into the app you're in.")
                        Toggle("", isOn: $prefs.enableSpokenRouting).toggleStyle(.switch).labelsHidden()
                    }
                }
                CDivider()
                CRow(title: "If you don't name a destination") {
                    Picker("", selection: $prefs.noRoutePolicy) {
                        Text("Type into the current app").tag(NoRoutePolicy.currentApp)
                        Text("Use the last destination").tag(NoRoutePolicy.lastDestination)
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                CDivider()
                CRow(title: "Submit automatically", subtitle: "Press Enter after pasting") {
                    Toggle("", isOn: $prefs.autoSubmit).toggleStyle(.switch).labelsHidden()
                }
            }

            HStack {
                CSection("Where you can send words")
                Spacer()
                Menu {
                    Button("Website…") { showAddWebsite = true }
                    Button("Quick-paste snippet…") { showAddSnippet = true }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.cadMedium(12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            CCard {
                ForEach(Array(destinations.enumerated()), id: \.element.id) { index, dest in
                    if index > 0 { CDivider() }
                    CRow(
                        title: dest.displayName,
                        subtitle: dest.aliases.prefix(3).map { "\u{201C}\($0)\u{201D}" }.joined(separator: "  ")
                    ) {
                        if isCustom(dest) {
                            Button {
                                CustomDestinationsStore().remove(id: dest.id)
                                refresh()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Built-in")
                                .font(.cadBody(10.5))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddWebsite) { AddWebsiteSheet(onDone: refresh) }
        .sheet(isPresented: $showAddSnippet) { AddSnippetSheet(onDone: refresh) }
    }

    private func isCustom(_ dest: Destination) -> Bool {
        !DestinationRegistry.builtIns().contains { $0.id == dest.id }
    }

    private func refresh() {
        destinations = DestinationRegistry.shared.destinations
    }
}

private struct AddWebsiteSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""
    @State private var openInPopup = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a website")
                .font(.cadTitle(16))
                .foregroundStyle(Color.textPrimary)
            Text("Give it a name you can say — \u{201C}Hey \(name.isEmpty ? "Inbox" : name), \u{2026}\u{201D}")
                .font(.cadBody(12))
                .foregroundStyle(Color.textSecondary)
            TextField("Name (what you'll say)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("https://…", text: $urlText)
                .textFieldStyle(.roundedBorder)
            Toggle("Open in the floating popup", isOn: $openInPopup)
                .font(.cadBody(12))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    if let url = URL(string: urlText), !name.isEmpty {
                        CustomDestinationsStore().add(name: name, url: url, openInPopup: openInPopup)
                        onDone()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || URL(string: urlText) == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color.melloSurface)
    }
}

private struct AddSnippetSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var snippet = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a quick-paste snippet")
                .font(.cadTitle(16))
                .foregroundStyle(Color.textPrimary)
            Text("Say \u{201C}Hey \(keyword.isEmpty ? "email" : keyword)\u{201D} and Cadence pastes the snippet.")
                .font(.cadBody(12))
                .foregroundStyle(Color.textSecondary)
            TextField("Keyword (what you'll say)", text: $keyword)
                .textFieldStyle(.roundedBorder)
            TextField("Text to paste", text: $snippet, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    if !keyword.isEmpty, !snippet.isEmpty {
                        CustomDestinationsStore().addSnippet(keyword: keyword, snippet: snippet)
                        onDone()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyword.isEmpty || snippet.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color.melloSurface)
    }
}

// MARK: - History

struct HistoryPane: View {
    @ObservedObject private var prefs = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CCard {
                CRow(title: "Save dictation history",
                     subtitle: "Stored on this Mac only — text, never audio") {
                    Toggle("", isOn: $prefs.saveDictationHistory).toggleStyle(.switch).labelsHidden()
                }
            }

            if prefs.saveDictationHistory {
                HistoryView(embedded: true)
                    .frame(minHeight: 300)
            } else {
                CCard {
                    CEmptyState(
                        icon: "clock",
                        title: "History is off",
                        message: "Turn it on to keep a local record of what you dictate.",
                        actionTitle: "Turn on history"
                    ) {
                        prefs.saveDictationHistory = true
                    }
                }
            }
        }
    }
}

// MARK: - Account

struct AccountPane: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var billing = BillingService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CCard {
                CRow(
                    title: auth.isSignedIn ? (auth.userEmail ?? "Signed in") : "Not signed in",
                    subtitle: auth.isSignedIn
                        ? (auth.isAnonymous ? "Guest session" : "Cadence Cloud")
                        : "Sign in to use cloud transcription"
                ) {
                    if auth.isSignedIn {
                        Text(auth.plan == "pro" ? "Pro" : "Free")
                            .font(.cadMedium(11))
                            .foregroundStyle(auth.plan == "pro" ? Color.melloInk : Color.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(auth.plan == "pro" ? Color.mello : Color.surfaceHover))
                    } else {
                        Button("Sign in") { SignInWindowController.shared.showWindow(nil) }
                            .controlSize(.small)
                    }
                }
            }

            if auth.isSignedIn {
                CSection("Plan")
                CCard {
                    if auth.plan == "pro" {
                        CRow(title: "Cadence Pro", subtitle: "Unlimited dictation") {
                            Button("Manage subscription") { billing.openManageSubscription() }
                                .controlSize(.small)
                        }
                    } else {
                        CRow(title: "Free plan", subtitle: "About 3 hours of talking a month") {
                            Button("Upgrade to Pro") { PaywallWindowController.shared.present() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        if auth.quotaLimitSeconds > 0 {
                            CDivider()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("This month")
                                        .font(.cadBody(12))
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                    Text("\(Int(max(0, auth.quotaLimitSeconds - auth.quotaUsedSeconds) / 60)) min left")
                                        .font(.cadMono(11))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                ProgressView(value: min(auth.quotaUsedSeconds, auth.quotaLimitSeconds),
                                             total: auth.quotaLimitSeconds)
                                    .tint(.mello)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }

                CCard {
                    CRow(title: "Sign out") {
                        Button("Sign out") { auth.signOut() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .onAppear { auth.fetchQuota() }
    }
}
