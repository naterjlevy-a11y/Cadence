import SwiftUI
import WebKit

/// In-app Stripe Embedded Checkout via WKWebView.
struct CheckoutWebView: NSViewRepresentable {
    let url: URL
    let completeURLPrefix: String
    let onComplete: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.completeURLPrefix = completeURLPrefix
        context.coordinator.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completeURLPrefix: completeURLPrefix, onComplete: onComplete)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var completeURLPrefix: String
        var onComplete: () -> Void

        init(completeURLPrefix: String, onComplete: @escaping () -> Void) {
            self.completeURLPrefix = completeURLPrefix
            self.onComplete = onComplete
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url?.absoluteString,
               url.hasPrefix(completeURLPrefix) || url.contains("checkout=complete") {
                onComplete()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Sheet wrapper for embedded checkout.
struct EmbeddedCheckoutSheet: View {
    @ObservedObject private var billing = BillingService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Upgrade to Mellotron Pro")
                    .font(.melloDisplay(18))
                Spacer()
                Button {
                    billing.dismissCheckout()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if let url = billing.embeddedCheckoutURL {
                CheckoutWebView(
                    url: url,
                    completeURLPrefix: billing.checkoutCompleteURLPrefix,
                    onComplete: {
                        billing.handleCheckoutComplete()
                        dismiss()
                    }
                )
            } else {
                ProgressView("Loading checkout…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 480, minHeight: 640)
        .mellotronThemed()
    }
}
