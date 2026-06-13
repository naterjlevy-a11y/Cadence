import Foundation
import AppKit
import SwiftUI

/// Standalone Pro upgrade window. Opened from the menu bar and Settings.
final class PaywallWindowController: NSWindowController {
    static let shared = PaywallWindowController()

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
        window.title = "Mellotron Pro"
        window.center()
        self.init(window: window)
        window.contentView = NSHostingView(rootView: PaywallView(onClose: { [weak self] in
            self?.close()
        }))
    }

    func present() {
        BillingService.shared.reset()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
