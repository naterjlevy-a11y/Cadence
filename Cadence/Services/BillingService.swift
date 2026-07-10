import Foundation
import AppKit
import Combine

/// Drives Stripe subscriptions through the Cadence Cloud worker.
///
/// Upgrade opens Stripe Embedded Checkout inside the app (WKWebView). Manage
/// subscription still uses the hosted Customer Portal in the browser.
@MainActor
final class BillingService: ObservableObject {
    static let shared = BillingService()

    enum Phase: Equatable {
        case idle
        case loading
        case checkout(URL)   // embedded checkout page URL loaded in-app
        case awaitingReturn  // portal opened in browser
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var showEmbeddedCheckout = false

    /// Prefix matched when Stripe redirects after successful embedded checkout.
    private(set) var checkoutCompleteURLPrefix: String = "https://cadence.app/welcome"

    let priceDisplay = "$5"
    let pricePeriod = "month"

    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.handleReturnToApp() }
            .store(in: &cancellables)
    }

    var isPro: Bool { AuthService.shared.plan == "pro" }

    var embeddedCheckoutURL: URL? {
        if case let .checkout(url) = phase { return url }
        return nil
    }

    // MARK: - Upgrade

    func startUpgrade() {
        phase = .loading
        showEmbeddedCheckout = false
        AuthService.shared.ensureCloudSessionReady { [weak self] ready in
            guard let self else { return }
            Task { @MainActor in
                guard ready, let token = AuthService.shared.accessToken, !token.isEmpty else {
                    self.phase = .failed("Sign in to Cadence Cloud first.")
                    return
                }
                await self.createEmbeddedCheckout(token: token)
            }
        }
    }

    func openManageSubscription() {
        phase = .loading
        guard let token = AuthService.shared.accessToken, !token.isEmpty else {
            phase = .failed("Sign in to manage your subscription.")
            return
        }
        Task { await createPortalSession(token: token) }
    }

    func handleCheckoutComplete() {
        showEmbeddedCheckout = false
        phase = .idle
        AuthService.shared.fetchQuota()
        pollPlanRefresh()
    }

    func dismissCheckout() {
        showEmbeddedCheckout = false
        if case .checkout = phase { phase = .idle }
    }

    func reset() { phase = .idle; showEmbeddedCheckout = false }

    // MARK: - Networking

    private func createEmbeddedCheckout(token: String) async {
        guard let base = CloudConfig.shared.apiBaseURL else {
            phase = .failed("Cadence Cloud is not configured.")
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("v1/checkout"))
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["embedded": true])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            guard status == 200,
                  let parsed = obj,
                  let clientSecret = parsed["client_secret"] as? String else {
                let detail = (obj?["detail"] as? String) ?? (obj?["error"] as? String)
                phase = .failed(detail ?? "Couldn't start checkout (HTTP \(status)).")
                return
            }

            let pk = (parsed["publishable_key"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? CloudConfig.shared.stripePublishableKey
            guard !pk.isEmpty else {
                phase = .failed("Stripe publishable key is not configured.")
                return
            }

            if let returnURL = parsed["return_url"] as? String, !returnURL.isEmpty {
                checkoutCompleteURLPrefix = returnURL.components(separatedBy: "?").first ?? returnURL
            }

            guard var components = URLComponents(
                url: CloudConfig.shared.embeddedCheckoutBaseURL ?? base.appendingPathComponent("embedded-checkout"),
                resolvingAgainstBaseURL: false
            ) else {
                phase = .failed("Invalid checkout URL.")
                return
            }
            components.queryItems = [
                URLQueryItem(name: "client_secret", value: clientSecret),
                URLQueryItem(name: "pk", value: pk),
            ]
            guard let pageURL = components.url else {
                phase = .failed("Invalid checkout URL.")
                return
            }

            phase = .checkout(pageURL)
            showEmbeddedCheckout = true
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func createPortalSession(token: String) async {
        guard let base = CloudConfig.shared.apiBaseURL else {
            phase = .failed("Cadence Cloud is not configured.")
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("v1/portal"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                phase = .failed("No subscription found yet.")
                return
            }
            guard status == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = obj["url"] as? String,
                  let url = URL(string: urlString) else {
                phase = .failed("Couldn't open subscription management.")
                return
            }
            NSWorkspace.shared.open(url)
            phase = .awaitingReturn
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Plan refresh

    private func handleReturnToApp() {
        guard phase == .awaitingReturn else { return }
        pollPlanRefresh()
    }

    private func pollPlanRefresh() {
        var attempts = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            attempts += 1
            AuthService.shared.fetchQuota()
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.isPro || attempts >= 5 {
                    timer.invalidate()
                    if case .awaitingReturn = self.phase { self.phase = .idle }
                }
            }
        }
    }
}
