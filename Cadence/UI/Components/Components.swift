import SwiftUI
import AppKit

// MARK: - Card

/// Flat settings card: hairline border, whisper of fill, generous padding.
struct CCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.strokeHairline, lineWidth: 1)
            )
    }
}

// MARK: - Row

/// The one true settings row: label left, control right, optional one-line
/// subtitle. 40pt min height. Compose inside CCard with CDivider between.
struct CRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cadBody(13))
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.cadBody(11))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
    }
}

/// Hairline divider between rows inside a card.
struct CDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.strokeHairline)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

// MARK: - Section header

/// Small sentence-case section header above a card.
struct CSection: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.cadLabel(11.5))
            .foregroundStyle(Color.textSecondary)
            .padding(.leading, 2)
    }
}

// MARK: - Sidebar item

struct CSidebarItem: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.mello : Color.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(selected ? .cadMedium(13) : .cadBody(13))
                    .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.surfaceHover : hovering ? Color.surfaceCard : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Keycap badge

/// A physical-looking key badge for shortcuts: `⌥ Right Option`.
struct CKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.cadMono(11, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.strokeHairline, lineWidth: 1)
            )
    }
}

// MARK: - Empty state

struct CEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text(title)
                .font(.cadMedium(13))
                .foregroundStyle(Color.textSecondary)
            if let message {
                Text(message)
                    .font(.cadBody(12))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Status dot

struct CStatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Color.green.opacity(0.85) : Color.orange.opacity(0.9))
            .frame(width: 7, height: 7)
    }
}

// MARK: - Info hint

/// Small ⓘ that reveals help text in a popover — replaces explainer cards.
struct CInfoHint: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(text)
                .font(.cadBody(12))
                .foregroundStyle(Color.textPrimary)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}
