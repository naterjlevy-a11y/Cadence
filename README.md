# Cadence

A native macOS push-to-talk dictation router. Hold a key, say where your words should go ("Hey Claude…", "Hey Google Docs…"), speak, release. Cadence opens or focuses the destination, strips the routing phrase, cleans up your speech, and pastes the result.

> Hold one key. Say where it goes. Speak your thought. Release. Done.

## Quick start

Requirements:

- macOS 14 or later
- Xcode 16 or later (project was generated with Xcode 26.5)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) only if you want to regenerate `Cadence.xcodeproj` from `project.yml`

Build and run:

```bash
cd ~/Projects/Cadence
xcodegen generate            # only needed if project.yml changes
open Cadence.xcodeproj
# or, from CLI:
xcodebuild -project Cadence.xcodeproj \
           -scheme Cadence \
           -configuration Debug \
           build
open build/DerivedData/Build/Products/Debug/Cadence.app
```

### Code signing (important for daily dev)

In Xcode → **Settings → Accounts**, add your Apple ID, then on the Cadence target pick your **Personal Team**. Do **not** force ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`); unstable signatures make macOS re-prompt for Keychain and silently break Accessibility / Input Monitoring.

After the first signed build, run **Permission Repair** once from the menu bar if any toggle looks stuck.

The first launch shows a 6-step onboarding flow (welcome + optional sign-in, how it works, permissions, push-to-talk key, live test, done).

## Permissions

Cadence requests:

- **Microphone** — captures audio only while you hold the push-to-talk key.
- **Speech Recognition** — transcribes audio on-device using Apple Speech.
- **Accessibility** — focuses apps and synthesizes the paste keystroke.
- **Input Monitoring** — detects the configured global push-to-talk key.
- **Apple Events** — opens or activates apps like Claude, Cursor, Notes (granted on first use).

The first run guides the user through each one on a single permissions screen; status and **Permission Repair** live under **Settings → Privacy & Permissions** and the menu bar.

## Architecture

```
App entry          CadenceApp                       (App/CadenceApp.swift)
                       │
Menu bar UI        MenuBarController                  (UI/MenuBar)
Onboarding         OnboardingFlowView                 (UI/Onboarding)
Settings           SettingsRootView                   (UI/Settings)
History            HistoryView                        (UI/History)
Recording HUD      RecordingIndicatorController       (UI/Indicator)
                       │
                       ▼
Hotkey             HotkeyManager  ── CGEvent tap    (Managers/HotkeyManager.swift)
                       │
                       ▼
Coordinator        DictationCoordinator (state machine)
                       │
            ┌──────────┼─────────────┬──────────────┐
            ▼          ▼             ▼              ▼
        Audio     Transcription   Cleanup        Routing
       Recorder    Service        Service       Phrase Parser
            │
            ▼
        Launch        Paste
        Manager       Manager
```

### Key files

| File | Purpose |
| --- | --- |
| `App/CadenceApp.swift` | NSApplicationDelegate, wires hotkey → coordinator and owns the menu bar. |
| `Managers/PermissionsManager.swift` | Tracks mic / speech / accessibility / input monitoring states and exposes them to SwiftUI. |
| `Managers/HotkeyManager.swift` | Global `CGEvent` tap that detects the configured PTT key (Right Ctrl/Opt/Cmd/Shift, Caps Lock, Fn/Globe, F-keys, custom). |
| `Managers/AudioRecorder.swift` | `AVAudioEngine` capture → 16 kHz mono Int16 WAV file with a live level meter. |
| `Services/TranscriptionService.swift` | Pluggable provider; default uses Apple Speech with on-device recognition when available. |
| `Services/CleanupService.swift` | Deterministic rule-based cleanup: filler removal, punctuation, capitalization, list formatting, personal dictionary. |
| `Managers/RoutingPhraseParser.swift` | Parses `Hey <destination>…` / `Ask <destination>…` etc., longest-match aliases, leaves the rest as content. |
| `Models/Destination.swift` | Built-in registry: Claude, ChatGPT, Gemini, Google Docs, Cursor, Notes, Perplexity, Gmail, Slack, plus a "Current App" fallback. |
| `Managers/LaunchManager.swift` | Decides whether to focus a running app, launch a native app, or open a URL in the user's preferred browser. |
| `Managers/PasteManager.swift` | Snapshots the clipboard, sets the cleaned text, synthesizes Cmd-V via `CGEvent`, optionally restores the previous clipboard. |
| `Managers/DictationCoordinator.swift` | Drives the full flow as a state machine and emits `@Published` state for the menu bar + indicator UI. |

## Default destinations

| Destination | Aliases (longest-match wins) | Mode |
| --- | --- | --- |
| Claude | claude, cloud, anthropic | native preferred → website |
| ChatGPT | chatgpt, chat gpt, gpt, open ai, chachi pt, chat gbt | native preferred → website |
| Gemini | gemini, google gemini, bard | website only |
| Google Docs | google docs, google doc, docs, document | website only |
| Cursor | cursor, code editor, my editor | native only |
| Apple Notes | notes, apple notes, note | native only |
| Perplexity | perplexity, search ai | native preferred → website |
| Gmail | gmail, google mail | website only |
| Slack | slack | native preferred → website |
| Current App | here, this, current app, right here | stay in current app |

Custom aliases per destination, plus enabling/disabling and per-destination preferred mode + auto-submit + paste delay, are configurable in **Settings → Destinations**.

## Routing examples

```
You say:    "Hey Claude, help me write a product spec."
Cadence:  Focuses or opens Claude
            Pastes: "Help me write a product spec."

You say:    "Open Google Docs and write a paragraph about renewable energy."
Cadence:  Opens Google Docs in your preferred browser
            Pastes: "Write a paragraph about renewable energy."

You say:    "Make this sound more professional."
Cadence:  Stays in the current app
            Pastes: "Make this sound more professional."

You say:    "Hey, Claude told me this might work."
Cadence:  No leading routing phrase detected — pastes verbatim into current app.
```

## Privacy posture

- Audio is captured **only** while the push-to-talk key is held.
- Transcription uses Apple Speech with `requiresOnDeviceRecognition = true` whenever available.
- Raw audio files are deleted as soon as transcription finishes. Setting **Privacy → Save raw audio** preserves them.
- Dictation history is **off by default**. When on, it stores cleaned text + destination + timestamp only — never raw audio.
- The clipboard is snapshotted before paste and restored ~600 ms later (toggle in Privacy settings).
- Logs avoid sensitive content unless **Settings → General → Verbose debug logging** is on.

## Roadmap (PRD §22 + §23)

Implemented in MVP:

- All §22.1 must-haves
- Personal dictionary, custom destination aliases, dictation history, launch at login, browser preference, retry-paste fallback (paste failure copies the cleaned text to the clipboard).

Future:

- Live destination detection while recording (PRD §23.3)
- Local Whisper transcription (PRD §23.4)
- Voice correction commands (PRD §23.5)
- Browser tab search across Chrome / Safari / Arc / Edge (PRD §15.3 advanced)
- Automatic Google Docs document selection (PRD §14.4 future)
- Per-app prompt styles (PRD §23.2)

## License

MIT
