import Foundation
import AppKit
import SwiftUI

/// Standalone sign-in window. Opened from Settings → Mellotron Cloud → "Sign in"
/// and from the Onboarding flow. Hosts ``SignInView``.
final class SignInWindowController: NSWindowController {
    static let shared = SignInWindowController()

    private convenience init() {
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Sign in to Mellotron"
        window.center()
        self.init(window: window)
        window.contentView = NSHostingView(rootView: SignInView(onClose: { [weak self] in
            self?.close()
        }))
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
