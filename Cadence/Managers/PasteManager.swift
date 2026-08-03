import Foundation
import AppKit
import Carbon.HIToolbox

/// Pastes text into the foreground application by:
/// 1) Snapshotting the current pasteboard (so we can restore later),
/// 2) Setting the pasteboard to the dictated text,
/// 3) Synthesizing Cmd-V via `CGEvent`,
/// 4) Optionally restoring the previous pasteboard contents after a delay.
final class PasteManager {
    static let shared = PasteManager()

    /// A snapshot of the pasteboard so we can restore it later.
    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    /// Bumped to abandon an in-flight paste chain.
    ///
    /// The retry chain is a series of `asyncAfter` hops spanning up to ~1.2s for
    /// a 3-attempt web destination. Nothing used to hold or cancel them, and
    /// `DictationCoordinator.cancel()` only cancelled transcription and polish.
    /// So a user who hit Escape or Cmd-Tabbed mid-chain still got attempts 2
    /// and 3 synthesizing Cmd-V into whatever app was now frontmost — and with
    /// `autoSubmit` on, a Return after it. Dictated text landing in the wrong
    /// app is bad; dictated text being *sent* from the wrong app is worse.
    private var generation = 0

    /// Abandon any in-flight paste chain. Safe to call when none is running.
    func cancelPending() {
        generation &+= 1
    }

    /// Paste `text` into the frontmost app. Web destinations often need a few
    /// tries because the page may still be loading when we first send Cmd-V.
    /// `focusInputShortcut` (e.g. "cmd+l") is sent BEFORE the paste so the
    /// destination app can move keyboard focus into its chat / message input.
    func paste(
        text: String,
        autoSubmit: Bool,
        pasteAttempts: Int = 1,
        focusInputShortcut: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !text.isEmpty else {
            completion(.failure(DictationError.pasteFailed("Empty text")))
            return
        }

        let pb = NSPasteboard.general
        let snapshot = UserPreferences.shared.preserveClipboard ? snapshotPasteboard(pb) : nil
        let attempts = max(1, pasteAttempts)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // Send the focus shortcut first if the destination has one. We give
        // the app a beat to react before pasting.
        if let combo = focusInputShortcut, let key = Self.parseShortcut(combo) {
            _ = simulateKey(virtualKey: key.keyCode, flags: key.flags)
        }

        let preFocusDelay: TimeInterval = focusInputShortcut == nil ? 0.08 : 0.22

        // Everything below is gated on two things: the chain still being the
        // current one, and the target app still being frontmost.
        generation &+= 1
        let gen = generation
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        func stillValid() -> Bool {
            guard gen == self.generation else {
                Log.paste.info("Paste chain abandoned — superseded or cancelled")
                return false
            }
            let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            guard current == targetApp else {
                Log.paste.warning("Paste chain aborted — frontmost app changed")
                return false
            }
            return true
        }

        func attemptPaste(remaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + preFocusDelay) {
                guard stillValid() else {
                    self.restoreSnapshot(snapshot, on: pb, after: 0.1)
                    completion(.failure(DictationError.pasteFailed("Paste cancelled.")))
                    return
                }

                let pasted = self.simulateCommandV()
                if !pasted {
                    completion(.failure(DictationError.pasteFailed("Could not synthesize Cmd-V — Accessibility may be missing.")))
                    self.restoreSnapshot(snapshot, on: pb, after: 0.4)
                    return
                }

                if remaining > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard stillValid() else {
                            self.restoreSnapshot(snapshot, on: pb, after: 0.1)
                            completion(.failure(DictationError.pasteFailed("Paste cancelled.")))
                            return
                        }
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        attemptPaste(remaining: remaining - 1)
                    }
                    return
                }

                if autoSubmit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        // Never send Return into an app the user has moved to.
                        guard stillValid() else { return }
                        _ = self.simulateReturn()
                    }
                }

                self.restoreSnapshot(snapshot, on: pb, after: 0.6)
                completion(.success(()))
            }
        }

        attemptPaste(remaining: attempts)
    }

    // MARK: - Synthesis

    private func simulateCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func simulateReturn() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let returnKey: CGKeyCode = CGKeyCode(kVK_Return)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) else {
            return false
        }
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func simulateKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    /// Parse "cmd+l" / "cmd+shift+i" / "cmd+/" into a (keyCode, flags) pair.
    private static func parseShortcut(_ combo: String) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = parts.last, !keyToken.isEmpty else { return nil }

        var flags: CGEventFlags = []
        for token in parts.dropLast() {
            switch token {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }

        let keyCode: CGKeyCode
        switch keyToken {
        case "a": keyCode = CGKeyCode(kVK_ANSI_A)
        case "b": keyCode = CGKeyCode(kVK_ANSI_B)
        case "c": keyCode = CGKeyCode(kVK_ANSI_C)
        case "d": keyCode = CGKeyCode(kVK_ANSI_D)
        case "e": keyCode = CGKeyCode(kVK_ANSI_E)
        case "f": keyCode = CGKeyCode(kVK_ANSI_F)
        case "g": keyCode = CGKeyCode(kVK_ANSI_G)
        case "h": keyCode = CGKeyCode(kVK_ANSI_H)
        case "i": keyCode = CGKeyCode(kVK_ANSI_I)
        case "j": keyCode = CGKeyCode(kVK_ANSI_J)
        case "k": keyCode = CGKeyCode(kVK_ANSI_K)
        case "l": keyCode = CGKeyCode(kVK_ANSI_L)
        case "m": keyCode = CGKeyCode(kVK_ANSI_M)
        case "n": keyCode = CGKeyCode(kVK_ANSI_N)
        case "o": keyCode = CGKeyCode(kVK_ANSI_O)
        case "p": keyCode = CGKeyCode(kVK_ANSI_P)
        case "q": keyCode = CGKeyCode(kVK_ANSI_Q)
        case "r": keyCode = CGKeyCode(kVK_ANSI_R)
        case "s": keyCode = CGKeyCode(kVK_ANSI_S)
        case "t": keyCode = CGKeyCode(kVK_ANSI_T)
        case "u": keyCode = CGKeyCode(kVK_ANSI_U)
        case "v": keyCode = CGKeyCode(kVK_ANSI_V)
        case "w": keyCode = CGKeyCode(kVK_ANSI_W)
        case "x": keyCode = CGKeyCode(kVK_ANSI_X)
        case "y": keyCode = CGKeyCode(kVK_ANSI_Y)
        case "z": keyCode = CGKeyCode(kVK_ANSI_Z)
        case "/", "slash": keyCode = CGKeyCode(kVK_ANSI_Slash)
        case ".", "period": keyCode = CGKeyCode(kVK_ANSI_Period)
        case ",", "comma": keyCode = CGKeyCode(kVK_ANSI_Comma)
        case "return", "enter": keyCode = CGKeyCode(kVK_Return)
        case "space": keyCode = CGKeyCode(kVK_Space)
        case "tab": keyCode = CGKeyCode(kVK_Tab)
        default: return nil
        }
        return (keyCode, flags)
    }

    // MARK: - Snapshot/restore

    private func snapshotPasteboard(_ pb: NSPasteboard) -> PasteboardSnapshot? {
        guard let items = pb.pasteboardItems else { return nil }
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var bag: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    bag[type] = data
                }
            }
            snapshot.append(bag)
        }
        return PasteboardSnapshot(items: snapshot)
    }

    private func restoreSnapshot(_ snapshot: PasteboardSnapshot?, on pb: NSPasteboard, after delay: TimeInterval) {
        guard let snapshot else { return }
        // Remember where the pasteboard was when we scheduled this. If the user
        // copies something during the delay, that's newer than what we're
        // holding and restoring would silently destroy it.
        let expectedChangeCount = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pb.changeCount == expectedChangeCount else {
                Log.paste.info("Skipped pasteboard restore — user copied something newer")
                return
            }
            pb.clearContents()
            for bag in snapshot.items {
                let item = NSPasteboardItem()
                for (type, data) in bag {
                    item.setData(data, forType: type)
                }
                pb.writeObjects([item])
            }
            Log.paste.info("Restored previous pasteboard contents (\(snapshot.items.count) items)")
        }
    }
}
