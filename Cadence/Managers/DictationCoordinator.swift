import Foundation
import AppKit
import Combine

extension Notification.Name {
    /// Posted when the user cancels an in-progress recording from the UI
    /// (Escape, X badge, etc). Listened to by the HotkeyManager so it can
    /// reset its hybrid/double-tap state.
    static let cadenceUserCancelled = Notification.Name("cadence.user.cancelled")
    /// Posted when hybrid mode latches into hands-free recording.
    static let cadenceDidLatch = Notification.Name("cadence.didLatch")
    /// Posted when hybrid mode unlatches.
    static let cadenceDidUnlatch = Notification.Name("cadence.didUnlatch")
    /// Posted when the user wants to open the menu bar popover from somewhere
    /// outside of MenuBarController (e.g. the indicator pill's "…" button).
    static let cadenceShowMenuPopover = Notification.Name("cadence.showMenuPopover")
    /// Posted to show a transient corner toast. `userInfo["message"]` is the text.
    static let cadenceShowToast = Notification.Name("cadence.showToast")
}

/// Coordinates the full hold-to-record -> transcribe -> route -> paste flow
/// as an async state machine. Drives the floating recording indicator and
/// menu bar status.
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    // MARK: - Published state

    @Published private(set) var stage: DictationStage = .idle {
        didSet {
            guard oldValue != stage else { return }
            Log.coordinator.info("STAGE \(oldValue.rawValue, privacy: .public) -> \(self.stage.rawValue, privacy: .public)")
        }
    }
    @Published private(set) var lastError: String?
    @Published private(set) var liveLevel: Float = 0
    @Published private(set) var lastDestinationName: String?
    @Published private(set) var lastFinalText: String?
    @Published private(set) var lastTranscriptionProvider: String?

    // MARK: - Components

    private let audio = AudioRecorder()
    private let transcription = TranscriptionService.shared
    private let cleanup = CleanupService.shared
    private let routingParser = RoutingPhraseParser()
    private let launch = LaunchManager.shared
    private let paste = PasteManager.shared

    private var levelObserver: AnyCancellable?
    private var sessionToken = UUID()
    private var watchdogTimer: Timer?
    /// Ultimate backstop: forcibly finalizes a `.recording` session if a
    /// key-release never reaches us (dropped NSEvent, crashed hotkey layer).
    /// The pill / mic can then never hang open indefinitely.
    private var recordingCapTimer: Timer?
    private var polishDeadlineWork: DispatchWorkItem?
    private var idleResetWork: DispatchWorkItem?
    private var polishFinished = false

    private init() {
        levelObserver = audio.$currentLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.liveLevel = level }
    }

    // MARK: - Public entry points

    /// Called by `HotkeyManager` when the PTT key goes down.
    func startRecording() {
        guard stage == .idle else {
            Log.coordinator.info("Ignoring start — stage is \(self.stage.rawValue, privacy: .public)")
            return
        }

        guard PermissionsManager.shared.microphone == .granted else {
            fail(with: DictationError.microphonePermissionDenied)
            return
        }

        beginSession()

        do {
            try audio.startRecording()
            stage = .recording
            startRecordingCap()
            SoundService.shared.playStart()
            Log.coordinator.info("Stage -> recording")
        } catch {
            invalidateSession()
            fail(with: error as? DictationError ?? .audioCaptureFailed(error.localizedDescription))
        }
    }

    /// Called by `HotkeyManager` when the PTT key is released.
    func stopRecording() {
        guard stage == .recording else { return }
        let token = sessionToken
        // Brief tail after key-up so the last syllable isn't clipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isActive(token), self.stage == .recording else { return }
            self.finishRecording(token: token)
        }
    }

    /// Arms the recording backstop. Fires a couple of seconds after the
    /// user's max-recording preference so the normal key-release path wins in
    /// every ordinary case; only a genuinely dropped release triggers it.
    private func startRecordingCap() {
        recordingCapTimer?.invalidate()
        let token = sessionToken
        let cap = TimeInterval(max(1, UserPreferences.shared.maximumRecordingSeconds)) + 2.0
        recordingCapTimer = Timer.scheduledTimer(withTimeInterval: cap, repeats: false) { [weak self] _ in
            guard let self, self.isActive(token), self.stage == .recording else { return }
            Log.coordinator.warning("Recording cap fired — no key-release arrived; finalizing session so the pill/mic can't hang.")
            self.finishRecording(token: token)
        }
    }

    private func stopRecordingCap() {
        recordingCapTimer?.invalidate()
        recordingCapTimer = nil
    }

    private func finishRecording(token: UUID) {
        stopRecordingCap()
        do {
            guard let result = try audio.stopRecording() else {
                fail(with: DictationError.audioCaptureFailed("Recording produced no audio"), token: token)
                return
            }

            let minMs = UserPreferences.shared.minimumHoldMilliseconds
            if result.duration * 1000 < Double(minMs) {
                Log.coordinator.info("Recording shorter than \(minMs, privacy: .public)ms — ignoring")
                cleanupTempFile(result.fileURL)
                invalidateSession()
                stage = .idle
                return
            }

            // No voice detected — drop it right here instead of sending silence
            // to the network (which makes Whisper hallucinate "Thank you",
            // "Satsang", etc.). This also makes the pill vanish the instant you
            // release the key when you didn't actually say anything.
            if Self.isSilentRecording(peak: result.peakPower, duration: result.duration) {
                Log.coordinator.info("No voice detected (peak \(result.peakPower, privacy: .public) dB) — dropping")
                cleanupTempFile(result.fileURL)
                invalidateSession()
                stage = .idle
                return
            }

            stage = .processingAudio
            startWatchdog(for: token, recordedSeconds: result.duration)
            transcribe(result: result, token: token)
        } catch {
            fail(with: error as? DictationError ?? .audioCaptureFailed(error.localizedDescription), token: token)
        }
    }

    /// Cancel an in-progress recording (Escape, X badge, etc).
    func cancel() {
        if stage == .recording {
            audio.cancel()
        }
        cancelInFlightWork()
        invalidateSession()
        stage = .idle
        lastError = nil
        NotificationCenter.default.post(name: .cadenceUserCancelled, object: nil)
    }

    /// Release the microphone. Called on app quit.
    func shutDownMic() {
        audio.shutDown()
    }

    func warmUpMic() {
        audio.warmUp()
    }

    // MARK: - Session management

    private func beginSession() {
        cancelInFlightWork()
        sessionToken = UUID()
    }

    private func invalidateSession() {
        cancelInFlightWork()
        sessionToken = UUID()
    }

    private func cancelInFlightWork() {
        transcription.cancelCurrent()
        AIPolishProvider.shared.cancel()
        AIRoutingProvider.shared.cancel()
        // The paste retry chain was the one piece of in-flight work this didn't
        // cancel, so Cmd-V kept firing into the foreground app after the user
        // had already bailed out.
        PasteManager.shared.cancelPending()
        polishDeadlineWork?.cancel()
        polishDeadlineWork = nil
        idleResetWork?.cancel()
        idleResetWork = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        recordingCapTimer?.invalidate()
        recordingCapTimer = nil
        polishFinished = false
    }

    private func isActive(_ token: UUID) -> Bool {
        sessionToken == token
    }

    private func startWatchdog(for token: UUID, recordedSeconds: TimeInterval = 0) {
        watchdogTimer?.invalidate()
        // This was a flat 8s, which was shorter than the network timeouts it
        // supervises: cloud transcription alone sets timeoutInterval = 25s and
        // polish 12s. With the default 300s max recording (~9.6MB of 16kHz
        // mono), the upload could never finish inside 8s, so every long
        // dictation died on "Took too long. Try again." — and leaked its WAV.
        //
        // Budget the stages we actually wait on, plus a slice for upload time
        // proportional to how much audio there is.
        let uploadAllowance = min(60.0, recordedSeconds * 0.5)
        let deadline = 25.0 + 12.0 + 5.0 + uploadAllowance
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { [weak self] _ in
            guard let self, self.isActive(token) else { return }
            switch self.stage {
            case .processingAudio, .transcribing, .detectingRoute,
                 .cleaningText, .resolvingDestination, .openingDestination,
                 .waitingForDestination, .pasting:
                Log.coordinator.warning("Watchdog: stage stuck at \(self.stage.rawValue, privacy: .public)")
                self.fail(with: .unknown("Took too long. Try again."), token: token)
            default:
                // .idle, .recording, .completed, .failed, .cancelling — leave alone.
                break
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    // MARK: - Stages

    private func transcribe(result: RecordingResult, token: UUID) {
        stage = .transcribing
        Log.coordinator.info("Stage -> transcribing")
        transcription.transcribe(fileURL: result.fileURL) { [weak self] outcome in
            DispatchQueue.main.async {
                // Delete the audio BEFORE the liveness guard. This used to sit
                // below it, so any late response for a superseded session
                // returned early and left the WAV in /tmp forever — despite the
                // app promising "audio deleted after transcription".
                self?.cleanupTempFile(result.fileURL)
                guard let self, self.isActive(token) else { return }
                switch outcome {
                case .success(let r):
                    Log.coordinator.info("Transcription confidence: \(r.confidence, privacy: .public)")
                    self.lastTranscriptionProvider = r.provider
                    if Self.isLikelyHallucination(r.text, duration: result.duration) {
                        Log.coordinator.info("Dropping likely silence hallucination: \(r.text, privacy: .private)")
                        self.invalidateSession()
                        self.stage = .idle
                        return
                    }
                    self.detectRoute(text: r.text, token: token)
                case .failure(let err):
                    self.fail(with: err as? DictationError ?? .transcriptionFailed(err.localizedDescription), token: token)
                }
            }
        }
    }

    private func detectRoute(text: String, token: UUID) {
        guard isActive(token) else { return }
        stage = .detectingRoute
        let parsed = routingParser.parse(text)
        Log.coordinator.info("Routing -> \(parsed.destination?.displayName ?? "<none>", privacy: .public)")

        // The user clearly tried to address a destination ("Hey …") but we
        // couldn't match it. Drop the text into the current app verbatim and
        // surface a non-blocking "Did you mean X?" hint in the corner.
        if parsed.destination == nil, let suggestion = parsed.didYouMean {
            NotificationCenter.default.post(
                name: .cadenceShowToast,
                object: nil,
                userInfo: ["message": "Destination not found. Did you mean \(suggestion)?"]
            )
        }

        finishDetectRoute(parsed: parsed, token: token)
    }

    private func finishDetectRoute(parsed: RouteParseResult, token: UUID) {
        guard isActive(token) else { return }

        // Prefetch app focus for short routing-only phrases like "Hey Email".
        if let dest = parsed.destination, parsed.matchedPhrase != nil {
            let trimmed = parsed.strippedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split { $0.isWhitespace }.count
            if trimmed.isEmpty || wordCount < 3 {
                prefetchLaunch(for: dest, subdestination: parsed.subdestination)
            }
        }

        cleanText(parsed: parsed, token: token)
    }

    /// Whisper (and Apple Speech) hallucinate boilerplate on silence/noise —
    /// "Thank you.", "Thanks for watching!", "Satsang with Mooji", subtitle
    /// credits, etc. When the *entire* transcript is one of these (and the clip
    /// was short), it's almost certainly silence — drop it instead of pasting.
    private static let hallucinationPhrases: Set<String> = [
        "thank you", "thank you.", "thanks for watching", "thanks for watching!",
        "thank you for watching", "please subscribe", "you", "you.", ".", ". .",
        "bye", "bye.", "okay", "okay.", "so", "so.", "i'm sorry", "subtitles",
        "subtitles by the amara.org community", "amara.org",
        "satsang", "satsang u", "satsang u.", "satsang with mooji",
        "transcription by", "transcribed by", "music", "[music]", "(music)",
        "the end", "the end.", "uh", "um", "hmm", "foreign", "silence",
        "(silence)", "[silence]", "[blank_audio]", "blank audio", "thank you very much",
        "see you", "see you next time", "see you in the next video", "1.5",
        "sous-titres", "sottotitoli",
    ]

    /// Decide whether a held recording contains real speech, purely from the
    /// loudness envelope. Conservative thresholds so we never drop genuine
    /// talking — only true silence / room tone.
    ///   • Real speech peaks well above −45 dB (usually −30 to −10).
    ///   • Quiet room tone sits around −55 to −48 dB.
    private static func isSilentRecording(peak: Float, duration: TimeInterval) -> Bool {
        if peak < -45 { return true }                       // essentially silent
        if duration < 0.9 && peak < -38 { return true }     // quick quiet misfire tap
        return false
    }

    private static func isLikelyHallucination(_ text: String, duration: TimeInterval) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let normalized = trimmed.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?,-"))
        if hallucinationPhrases.contains(normalized) { return true }
        if normalized.contains("satsang") || normalized.contains("amara.org") { return true }
        // Very short clip (< ~1.1s) that produced only a tiny fragment is
        // usually a misfire — Whisper rarely emits <4 chars for real speech.
        if duration < 1.1 && normalized.count <= 3 { return true }
        // Short clip that produced only a stock 1-2 word fragment — junk.
        let words = normalized.split(separator: " ").count
        if duration < 1.3 && words <= 2 && normalized.count <= 12 { return true }
        return false
    }

    private static func stripRoutingPrefix(from text: String, stripChars: Int) -> String {
        guard stripChars > 0, stripChars < text.count else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let idx = text.index(text.startIndex, offsetBy: min(stripChars, text.count))
        var remainder = String(text[idx...])
        if let first = remainder.first, first == "," || first == "." || first == ":" {
            remainder.removeFirst()
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prefetchLaunch(for destination: Destination, subdestination: Subdestination?) {
        let plan = launch.makePlan(for: destination, subdestination: subdestination)
        switch plan.action {
        case .focusRunningApp(let app):
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        case .openApp(let url):
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
        case .openPopup:
            // Delegate to LaunchManager so the user's popup-mode preference
            // (browser-app-window vs embedded WKWebView) is honored.
            launch.execute(plan) { _ in }
        default:
            break
        }
    }

    private func cleanText(parsed: RouteParseResult, token: UUID) {
        guard isActive(token) else { return }
        stage = .cleaningText

        let toClean = parsed.strippedText
        let trimmed = toClean.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split { $0.isWhitespace }.count
        let hasRoute = parsed.destination != nil && parsed.matchedPhrase != nil
        let isShortRouteOnly = hasRoute && (trimmed.isEmpty || wordCount < 3)

        // Fast path: "Hey Email" with no dictation content — open immediately.
        if isShortRouteOnly {
            resolveAndOpen(
                destination: parsed.destination!,
                subdestination: parsed.subdestination,
                finalText: nil,
                matchedPhrase: parsed.matchedPhrase,
                token: token
            )
            return
        }

        let context = CleanupContext(
            destinationId: parsed.destination?.id,
            destinationDisplayName: parsed.destination?.displayName,
            preserveTechnicalTerms: parsed.destination?.id == "cursor"
        )
        let aiOn = UserPreferences.shared.aiPolishEnabled
            && AIPolishProvider.shared.isAvailable
        var cleaned = aiOn
            ? cleanup.preCleanForAI(rawText: toClean, context: context)
            : cleanup.clean(rawText: toClean, context: context)
        if cleaned.isEmpty, !trimmed.isEmpty {
            cleaned = trimmed
            Log.coordinator.warning("Cleanup produced empty text — using stripped transcript")
        }
        if cleaned.isEmpty {
            if let destination = parsed.destination {
                // Quick-paste keywords ("Hey email") carry no spoken text — the
                // payload IS the saved snippet, so paste that instead of nothing.
                let snippetText = (destination.pasteSnippet?.isEmpty == false)
                    ? destination.pasteSnippet
                    : nil
                resolveAndOpen(
                    destination: destination,
                    subdestination: parsed.subdestination,
                    finalText: snippetText,
                    matchedPhrase: parsed.matchedPhrase,
                    token: token
                )
            } else {
                stage = .idle
                cancelInFlightWork()
            }
            return
        }

        if UserPreferences.shared.aiPolishEnabled,
           AIPolishProvider.shared.isAvailable {
            runPolishWithDeadline(parsed: parsed, cleaned: cleaned, token: token)
        } else {
            routeAfterClean(parsed: parsed, cleaned: cleaned, token: token)
        }
    }

    private func runPolishWithDeadline(parsed: RouteParseResult, cleaned: String, token: UUID) {
        polishFinished = false

        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.isActive(token), !self.polishFinished else { return }
            self.polishFinished = true
            Log.coordinator.warning("AI polish deadline — using rule-based text")
            AIPolishProvider.shared.cancel()
            self.routeAfterClean(parsed: parsed, cleaned: cleaned, token: token)
        }
        polishDeadlineWork = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: deadline)

        let flavor = Self.flavor(for: parsed.destination)
        AIPolishProvider.shared.polish(cleaned, destinationName: parsed.destination?.displayName, flavor: flavor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isActive(token) else { return }
                guard !self.polishFinished else { return }
                self.polishFinished = true
                self.polishDeadlineWork?.cancel()
                self.polishDeadlineWork = nil
                let polished = (try? result.get()) ?? cleaned
                self.routeAfterClean(parsed: parsed, cleaned: polished, token: token)
            }
        }
    }

    private func routeAfterClean(parsed: RouteParseResult, cleaned: String, token: UUID) {
        guard isActive(token) else { return }
        let destination = parsed.destination ?? defaultDestination()
        // Quick-paste keyword: ignore whatever was spoken after the keyword and
        // paste the saved snippet into the current app instead.
        let text: String
        if let snippet = destination.pasteSnippet, !snippet.isEmpty {
            text = snippet
        } else {
            text = cleaned
        }
        resolveAndOpen(
            destination: destination,
            subdestination: parsed.subdestination,
            finalText: text,
            matchedPhrase: parsed.matchedPhrase,
            token: token
        )
    }

    /// Map a destination to the LLM "flavor" hint — drives quote style and
    /// list formatting in the polish prompt.
    private static func flavor(for destination: Destination?) -> AIPolishProvider.DestinationFlavor {
        guard let destination else { return .generic }
        switch destination.id {
        case "cursor", "vs_code", "xcode", "terminal", "iterm", "ghostty":
            return .code
        case "google_docs", "apple_notes", "notion", "obsidian", "bear", "drafts",
             "apple_mail", "gmail", "outlook":
            return .document
        case "claude", "chatgpt", "gemini", "perplexity", "copilot", "grok":
            return .chat
        default:
            return .generic
        }
    }

    private func defaultDestination() -> Destination {
        let fallback = DestinationRegistry.shared.destination(withId: "current_app")
            ?? DestinationRegistry.builtIns().first { $0.id == "current_app" }!
        switch UserPreferences.shared.noRoutePolicy {
        case .lastDestination:
            let lastId = UserPreferences.shared.lastDestinationId
            return DestinationRegistry.shared.destination(withId: lastId) ?? fallback
        case .currentApp, .scratchpad, .ask:
            return fallback
        }
    }

    private func resolveAndOpen(
        destination: Destination,
        subdestination: Subdestination?,
        finalText: String?,
        matchedPhrase: String?,
        token: UUID
    ) {
        guard isActive(token) else { return }
        stage = .resolvingDestination
        let plan = launch.makePlan(for: destination, subdestination: subdestination)
        stage = .openingDestination
        if let subdestination {
            lastDestinationName = "\(destination.displayName) · \(subdestination.name)"
        } else {
            lastDestinationName = destination.displayName
        }
        UserPreferences.shared.lastDestinationId = destination.id
        let isStrictRoute = matchedPhrase != nil

        launch.execute(plan) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isActive(token) else { return }
                switch result {
                case .success:
                    if let finalText {
                        self.stage = .pasting
                        self.performPaste(
                            text: finalText,
                            destination: destination,
                            plan: plan,
                            matchedPhrase: matchedPhrase,
                            strict: isStrictRoute,
                            token: token
                        )
                    } else {
                        self.completeSuccessfully(
                            destination: destination,
                            finalText: "",
                            matchedPhrase: matchedPhrase,
                            token: token
                        )
                    }
                case .failure(let err):
                    self.fail(with: err as? DictationError ?? .unknown(err.localizedDescription), token: token)
                }
            }
        }
    }

    private func performPaste(
        text: String,
        destination: Destination,
        plan: LaunchPlan,
        matchedPhrase: String?,
        strict: Bool,
        token: UUID
    ) {
        let autoSubmit = destination.autoSubmitEnabled && UserPreferences.shared.autoSubmit
        lastFinalText = text
        let pasteAttempts = destination.preferredMode == .websiteOnly ? 3 : 1

        if strict, let expected = expectedFrontBundleId(for: plan) {
            ensureFrontmost(bundleId: expected, plan: plan, attempts: 3) { [weak self] frontOk in
                guard let self, self.isActive(token) else { return }
                if !frontOk {
                    Log.coordinator.error("Strict route: \(expected, privacy: .public) never became frontmost")
                    self.recordHistory(
                        destination: destination,
                        finalText: text,
                        matched: matchedPhrase,
                        success: false,
                        error: "Couldn't focus \(destination.displayName)."
                    )
                    self.fail(with: .pasteFailed("Couldn't focus \(destination.displayName)."), token: token)
                    return
                }
                self.runPaste(
                    text: text,
                    destination: destination,
                    autoSubmit: autoSubmit,
                    pasteAttempts: pasteAttempts,
                    matchedPhrase: matchedPhrase,
                    token: token
                )
            }
            return
        }

        runPaste(
            text: text,
            destination: destination,
            autoSubmit: autoSubmit,
            pasteAttempts: pasteAttempts,
            matchedPhrase: matchedPhrase,
            token: token
        )
    }

    private func runPaste(
        text: String,
        destination: Destination,
        autoSubmit: Bool,
        pasteAttempts: Int,
        matchedPhrase: String?,
        token: UUID
    ) {
        // Strict (routed) sends include the focus shortcut so the dictation
        // lands in the destination's chat input even if the user was on a
        // different page. Non-strict sends paste at the current caret.
        let focusShortcut = matchedPhrase != nil ? destination.focusInputShortcut : nil
        paste.paste(
            text: text,
            autoSubmit: autoSubmit,
            pasteAttempts: pasteAttempts,
            focusInputShortcut: focusShortcut
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isActive(token) else { return }
                switch result {
                case .success:
                    self.completeSuccessfully(
                        destination: destination,
                        finalText: text,
                        matchedPhrase: matchedPhrase,
                        token: token
                    )
                case .failure(let err):
                    self.recordHistory(
                        destination: destination,
                        finalText: text,
                        matched: matchedPhrase,
                        success: false,
                        error: err.localizedDescription
                    )
                    self.fail(with: err as? DictationError ?? .pasteFailed(err.localizedDescription), token: token)
                }
            }
        }
    }

    private func completeSuccessfully(
        destination: Destination,
        finalText: String,
        matchedPhrase: String?,
        token: UUID
    ) {
        guard isActive(token) else { return }
        stage = .completed
        stopWatchdog()
        SoundService.shared.playSend()
        recordHistory(
            destination: destination,
            finalText: finalText,
            matched: matchedPhrase,
            success: true,
            error: nil
        )
        scheduleIdleReset(from: .completed)
    }

    private func expectedFrontBundleId(for plan: LaunchPlan) -> String? {
        switch plan.action {
        case .focusRunningApp(let app):
            return app.bundleIdentifier
        case .openApp:
            return plan.destination.bundleId
        case .openWebsite(_, let browserBundleId):
            if let id = browserBundleId, !id.isEmpty { return id }
            return defaultBrowserBundleId()
        case .openPopup:
            // Popup activation is handled internally (LaunchManager waits
            // for the browser or WKWebView to be ready). We skip the strict
            // frontmost check here — paste will land in whatever's now
            // focused, which is the popup window in both modes.
            return nil
        case .stayInCurrentApp:
            return nil
        }
    }

    private func ensureFrontmost(
        bundleId: String,
        plan: LaunchPlan,
        attempts: Int,
        completion: @escaping (Bool) -> Void
    ) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front == bundleId {
            completion(true)
            return
        }
        guard attempts > 0 else {
            completion(false)
            return
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            running.activate(options: [])
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg, completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.ensureFrontmost(bundleId: bundleId, plan: plan, attempts: attempts - 1, completion: completion)
        }
    }

    private func defaultBrowserBundleId() -> String? {
        guard let url = URL(string: "http://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    // MARK: - Helpers

    private func fail(with error: DictationError, token: UUID? = nil) {
        if let token, !isActive(token) { return }
        Log.coordinator.error("Failed: \(error.localizedDescription, privacy: .public)")
        lastError = error.localizedDescription
        stage = .failed
        SoundService.shared.playFail()
        cancelInFlightWork()
        scheduleIdleReset(from: .failed)
    }

    private func scheduleIdleReset(from stage: DictationStage) {
        idleResetWork?.cancel()
        let delay: TimeInterval = stage == .failed ? 1.6 : 1.2
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.stage == stage {
                self.stage = .idle
                self.stopWatchdog()
            }
        }
        idleResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func recordHistory(
        destination: Destination,
        finalText: String,
        matched: String?,
        success: Bool,
        error: String?
    ) {
        guard UserPreferences.shared.saveDictationHistory else { return }
        let entry = DictationHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            destinationId: destination.id,
            destinationDisplayName: destination.displayName,
            finalText: finalText,
            routePhraseDetected: matched,
            pasteSucceeded: success,
            errorMessage: error
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        var history = UserPreferences.shared.dictationHistory
        history.insert(data, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        UserPreferences.shared.dictationHistory = history
    }

    func loadHistory() -> [DictationHistoryEntry] {
        UserPreferences.shared.dictationHistory.compactMap {
            try? JSONDecoder().decode(DictationHistoryEntry.self, from: $0)
        }
    }

    func clearHistory() {
        UserPreferences.shared.dictationHistory = []
    }
}
