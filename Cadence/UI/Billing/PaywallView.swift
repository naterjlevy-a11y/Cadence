import SwiftUI
import AppKit

/// Pro upgrade surface. Single plan, hosted Stripe Checkout in the browser.
struct PaywallView: View {
    let onClose: () -> Void

    @ObservedObject private var billing = BillingService.shared
    @ObservedObject private var auth = AuthService.shared

    private let proFeatures: [(icon: String, title: String, detail: String)] = [
        ("infinity", "Unlimited dictation", "No monthly minute cap — talk as much as you want."),
        ("bolt.fill", "Priority cloud transcription", "Fastest Groq Whisper lane, even at peak times."),
        ("wand.and.stars", "AI cleanup on every paste", "Punctuation, formatting, and filler removal, always on."),
        ("lock.open.fill", "Everything, everywhere", "All destinations and routing stay unlocked."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.melloInk.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                featureList
                    .padding(.horizontal, 36)
                    .padding(.top, 22)
                Spacer(minLength: 18)
                footer
                    .padding(.horizontal, 36)
                    .padding(.bottom, 24)
            }

            closeButton
                .padding(.top, 14)
                .padding(.trailing, 14)
        }
        .frame(width: 460, height: 620)
        .sheet(isPresented: $billing.showEmbeddedCheckout) {
            EmbeddedCheckoutSheet()
        }
        .cadenceThemed()
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 14) {
            BrandMark(size: 60)
                .padding(.top, 50)

            DisplayHeadline("Cadence ", size: 32, alignment: .center)
                .italic("Pro.")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(billing.priceDisplay)
                    .font(.melloDisplay(34))
                Text("/ \(billing.pricePeriod)")
                    .font(.melloBody(15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            Text("Cancel anytime. Billed securely through Stripe.")
                .font(.melloBody(12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var featureList: some View {
        VStack(spacing: 12) {
            ForEach(proFeatures, id: \.title) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mello)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.melloBody(13.5, weight: .semibold))
                        Text(feature.detail)
                            .font(.melloBody(11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 12) {
            if billing.isPro {
                Text("You're on Pro 🎉")
                    .font(.melloBody(14, weight: .semibold))
                    .foregroundStyle(Color.mello)
                Button("Manage subscription") { billing.openManageSubscription() }
                    .buttonStyle(.plain)
                    .font(.melloBody(12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                PaywallButton(
                    title: buttonTitle,
                    busy: isCheckoutLoading,
                    action: { billing.startUpgrade() }
                )
                Button("Maybe later", action: onClose)
                    .buttonStyle(.plain)
                    .font(.melloBody(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = billing.phase {
                Text(message)
                    .font(.melloBody(11.5))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if case .checkout = billing.phase {
                Text("Complete checkout in the sheet above.")
                    .font(.melloBody(11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var isCheckoutLoading: Bool {
        if case .loading = billing.phase { return true }
        return false
    }

    private var buttonTitle: String {
        switch billing.phase {
        case .loading: return "Loading…"
        case .checkout: return "Checkout open…"
        default:       return "Upgrade to Pro"
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

private struct PaywallButton: View {
    let title: String
    let busy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.melloBody(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(hovering ? Color.mello.opacity(0.96) : Color.mello)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.7 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
