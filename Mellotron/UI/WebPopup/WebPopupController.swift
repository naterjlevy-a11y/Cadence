import Foundation
import AppKit
import SwiftUI
import WebKit
import Combine

/// A floating web-popup pinned to a screen corner. Holds a single WKWebView
/// so the user can route dictation into a website without leaving their
/// current app full-screen (e.g. "Hey Gemini, …" pops Gemini in the corner
/// instead of stealing the foreground).
final class WebPopupController: NSObject {
    static let shared = WebPopupController()

    private var window: WebPopupWindow?
    private var hostingView: NSHostingView<WebPopupView>?
    private var viewModel: WebPopupViewModel?

    /// True if the popup is visible right now. The paste flow can use this
    /// to know we'll be the frontmost app, not the destination app.
    var isVisible: Bool {
        window?.isVisible == true
    }

    /// Bring the popup forward, navigating to `url` if it isn't already
    /// loaded there. Calls `completion` once the popup is the key window
    /// and the page has had a moment to settle.
    func open(url: URL, completion: @escaping () -> Void) {
        ensureWindow()
        guard let window, let viewModel else {
            completion()
            return
        }

        positionInCorner(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let store = viewModel.webView.configuration.websiteDataStore.httpCookieStore
        ChromeCookieImporter.shared.importIfNeeded(for: url.host, into: store) { result in
            switch result {
            case .disabled:
                viewModel.cookieImportBanner = nil
            case .success:
                viewModel.cookieImportBanner = nil
            case .failed:
                viewModel.cookieImportBanner =
                    "Couldn't read Chrome session — sign in once below (person icon)."
            }
            viewModel.load(url)

            // Let the WKWebView paint and the input field auto-focus before paste.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                completion()
            }
        }
    }

    func close() {
        window?.orderOut(nil)
    }

    private func ensureWindow() {
        if window != nil { return }

        let vm = WebPopupViewModel(onClose: { [weak self] in self?.close() })
        let view = WebPopupView(viewModel: vm)
        let hosting = NSHostingView(rootView: view)

        let size = NSSize(width: 380, height: 540)
        let window = WebPopupWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mellotron Popup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // .statusBar floats above .floating windows (Spotlight-style),
        // staying on top of normal app windows AND fullscreen apps when
        // combined with .fullScreenAuxiliary below.
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)

        self.window = window
        self.hostingView = hosting
        self.viewModel = vm
    }

    private func positionInCorner(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 16
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        )
        window.setFrameOrigin(origin)
    }
}

/// Subclass so the borderless panel can still become key (needed so the
/// WKWebView receives keyboard events for Cmd-V and direct typing).
final class WebPopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View model

final class WebPopupViewModel: ObservableObject {
    @Published var urlString: String = ""
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var cookieImportBanner: String?

    fileprivate let webView: WKWebView
    private let onClose: () -> Void
    private var observers: [NSKeyValueObservation] = []

    init(onClose: @escaping () -> Void) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.onClose = onClose

        observers.append(webView.observe(\.url) { [weak self] view, _ in
            DispatchQueue.main.async {
                self?.urlString = view.url?.absoluteString ?? ""
            }
        })
        observers.append(webView.observe(\.title) { [weak self] view, _ in
            DispatchQueue.main.async {
                self?.pageTitle = view.title ?? ""
            }
        })
        observers.append(webView.observe(\.isLoading) { [weak self] view, _ in
            DispatchQueue.main.async { self?.isLoading = view.isLoading }
        })
        observers.append(webView.observe(\.canGoBack) { [weak self] view, _ in
            DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
        })
        observers.append(webView.observe(\.canGoForward) { [weak self] view, _ in
            DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
        })
    }

    func load(_ url: URL) {
        if webView.url == url { return }
        webView.load(URLRequest(url: url))
    }

    /// Take the user to the Google sign-in page with a return URL that
    /// brings them right back to whatever page they were on. Cookies set
    /// here persist forever in our `.default()` data store so they only
    /// have to do this once.
    func signInToGoogle() {
        let returnTo = webView.url?.absoluteString ?? "https://www.google.com/"
        var components = URLComponents(string: "https://accounts.google.com/ServiceLogin")
        components?.queryItems = [URLQueryItem(name: "continue", value: returnTo)]
        guard let url = components?.url else { return }
        cookieImportBanner = nil
        webView.load(URLRequest(url: url))
    }

    func loadURLString(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let resolved: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            resolved = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            resolved = "https://\(trimmed)"
        } else {
            resolved = "https://www.google.com/search?q=" + (trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
        }
        guard let url = URL(string: resolved) else { return }
        webView.load(URLRequest(url: url))
    }

    func reload() { webView.reload() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func close() { onClose() }
    func copyURL() {
        guard let url = webView.url else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
}

// MARK: - SwiftUI body

private struct WebPopupView: View {
    @ObservedObject var viewModel: WebPopupViewModel
    @State private var urlEditing: String = ""
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chrome
            if let banner = viewModel.cookieImportBanner {
                Text(banner)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.mello.opacity(0.12))
            }
            Divider().opacity(0.4)
            WebViewHost(webView: viewModel.webView)
        }
        .background(
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
        )
        .mellotronThemed()
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            Button { viewModel.close() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close popup")

            Button { viewModel.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.canGoBack ? .primary : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoBack)
            .help("Back")

            Button { viewModel.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.canGoForward ? .primary : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoForward)
            .help("Forward")

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .help("Reload")

            TextField("", text: $urlEditing)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .focused($urlFocused)
                .onSubmit { viewModel.loadURLString(urlEditing) }
                .onChange(of: viewModel.urlString) { _, new in
                    if !urlFocused { urlEditing = new }
                }
                .onAppear { urlEditing = viewModel.urlString }

            Button { viewModel.copyURL() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy URL")

            Button { viewModel.signInToGoogle() } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mello)
            }
            .buttonStyle(.plain)
            .help("Sign in to Google — only needed once. Your session is saved.")

            Button { saveAsDestination() } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mello)
            }
            .buttonStyle(.plain)
            .help("Save as a destination — give it a name and route dictation here with \"Hey [name], …\"")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private extension WebPopupView {
    func saveAsDestination() {
        guard let url = viewModel.webView.url else { return }

        let alert = NSAlert()
        alert.messageText = "Save as destination"
        alert.informativeText = "Give it a spoken name. You can say \"Hey [name], …\" to route dictation here later."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: viewModel.pageTitle.trimmingCharacters(in: .whitespaces))
        field.placeholderString = "Name"
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        let popupCheckbox = NSButton(checkboxWithTitle: "Open in popup window", target: nil, action: nil)
        popupCheckbox.state = .on
        popupCheckbox.frame = NSRect(x: 0, y: 0, width: 280, height: 18)

        let container = NSStackView(views: [field, popupCheckbox])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.frame = NSRect(x: 0, y: 0, width: 280, height: 50)
        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        CustomDestinationsStore.shared.add(
            name: name,
            url: url,
            openInPopup: popupCheckbox.state == .on
        )
    }
}

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
