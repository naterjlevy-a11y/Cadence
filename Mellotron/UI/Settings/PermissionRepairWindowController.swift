import Foundation
import AppKit
import SwiftUI

/// A focused, full-window repair flow for macOS TCC permissions.
/// The single biggest source of confusion in this app is the "toggle is
/// ON in System Settings but the system still says denied" situation,
/// caused by ad-hoc rebuilds changing the binary's cdhash. This window
/// explains what's happening, surfaces stale duplicate copies of
/// Mellotron, and gives the user a one-click reset path.
final class PermissionRepairWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Permission Repair"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: PermissionRepairView())
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PermissionRepairView: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var duplicates: [URL] = AppRelocator.duplicateInstallations()
    @State private var repairBanner: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                hero
                runningCard
                duplicatesCard
                permissionsCard
                instructionsCard
            }
            .padding(28)
        }
        .frame(width: 560)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
        .mellotronThemed()
        .onAppear {
            permissions.startPolling()
            duplicates = AppRelocator.duplicateInstallations()
        }
        .onDisappear { permissions.stopPolling() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.mello)
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .heavy))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Repair")
                        .font(.melloDisplay(24))
                        .tracking(-0.2)
                    Text("Fix the \"toggle says on but it's denied\" problem in one click.")
                        .font(.melloBody(12))
                        .foregroundStyle(.secondary)
                }
            }

            if let banner = repairBanner {
                Text(banner)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.12))
                    )
            }
        }
    }

    // MARK: - Running app card

    private var runningCard: some View {
        RepairCard(title: "Running from", glyph: AppRelocator.isInApplications ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                   tint: AppRelocator.isInApplications ? .green : .orange) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppRelocator.runningPath)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                if AppRelocator.isInApplications {
                    Text("Good — when the app lives in /Applications, macOS keeps your permissions matched to it across rebuilds.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Permissions you grant here will not survive Xcode rebuilds. Move Mellotron to /Applications first.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Move to /Applications and relaunch") {
                        _ = AppRelocator.moveToApplicationsAndRelaunch()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Duplicates card

    @ViewBuilder
    private var duplicatesCard: some View {
        if duplicates.isEmpty {
            RepairCard(title: "Other copies on disk",
                       glyph: "checkmark.seal.fill",
                       tint: .green) {
                Text("No stray copies of Mellotron found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else {
            RepairCard(title: "Other copies on disk",
                       glyph: "doc.on.doc.fill",
                       tint: .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These extra copies confuse macOS — TCC may have permission entries pointing at them instead of the running app.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(duplicates, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.secondary)
                            Text(url.path)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                    }

                    Button {
                        let count = AppRelocator.trashDuplicates(duplicates)
                        duplicates = AppRelocator.duplicateInstallations()
                        repairBanner = "Moved \(count) duplicate\(count == 1 ? "" : "s") to the Trash."
                    } label: {
                        Label("Move all duplicates to Trash", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Permissions card

    private var permissionsCard: some View {
        RepairCard(title: "Permission status",
                   glyph: permissions.missingPermissions.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                   tint: permissions.missingPermissions.isEmpty ? .green : .orange) {
            VStack(spacing: 10) {
                permRow(name: "Microphone", state: permissions.microphone, kind: .microphone)
                Divider().opacity(0.4)
                permRow(name: "Speech Recognition", state: permissions.speechRecognition, kind: .speech)
                Divider().opacity(0.4)
                permRow(name: "Accessibility", state: permissions.accessibility, kind: .accessibility)
                Divider().opacity(0.4)
                permRow(name: "Input Monitoring", state: permissions.inputMonitoring, kind: .inputMonitoring)

                if !permissions.missingPermissions.isEmpty {
                    Divider().opacity(0.4)
                    Button {
                        permissions.resetAllAndReprompt()
                        repairBanner = "Cleared stale entries. Approve any system prompts that appear, or toggle in System Settings."
                    } label: {
                        Label("Reset all & re-prompt", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private func permRow(name: String, state: PermissionStatus, kind: TCCKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: glyph(for: state))
                .foregroundStyle(color(for: state))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(label(for: state))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Text("Granted").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            } else {
                Button("Repair") {
                    permissions.resetAndReprompt(kind)
                    repairBanner = "Reset \(name). Approve the prompt or toggle it on in System Settings."
                }
            }
        }
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        RepairCard(title: "Why this happens", glyph: "info.circle.fill", tint: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS keys Accessibility and Input Monitoring permissions to the exact code-signing identity of the binary. Ad-hoc development builds get a brand-new identity on every rebuild, so an entry that was granted yesterday is silently invalidated today — even though the toggle in System Settings still appears on.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reset all & re-prompt asks macOS to forget Mellotron entirely (via tccutil reset) so the next prompt registers the current build cleanly. Keep Mellotron in /Applications and sign with a free Apple Development Personal Team in Xcode — without stable signing, every rebuild can invalidate grants again.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func glyph(for state: PermissionStatus) -> String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        case .notDetermined, .unknown: return "circle"
        }
    }

    private func color(for state: PermissionStatus) -> Color {
        switch state {
        case .granted: return .green
        case .denied, .restricted: return .orange
        case .notDetermined, .unknown: return .secondary
        }
    }

    private func label(for state: PermissionStatus) -> String {
        switch state {
        case .granted: return "Working as expected"
        case .denied: return "Denied — toggle is stale, click Repair"
        case .restricted: return "Restricted by macOS"
        case .notDetermined: return "Not yet asked"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Card primitive

private struct RepairCard<Content: View>: View {
    let title: String
    let glyph: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .foregroundStyle(tint)
                    .font(.system(size: 12, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }
}

// MARK: - Visual effect background

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
