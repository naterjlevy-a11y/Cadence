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

        func attemptPaste(remaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + preFocusDelay) {
                let pasted = self.simulateCommandV()
                if !pasted {
                    completion(.failure(DictationError.pasteFailed("Could not synthesize Cmd-V — Accessibility may be missing.")))
                    self.restoreSnapshot(snapshot, on: pb, after: 0.4)
                    return
                }

                if remaining > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        attemptPaste(remaining: remaining - 1)
                    }
                    return
                }

                if autoSubmit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
