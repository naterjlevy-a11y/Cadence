import Foundation
import AppKit
import SwiftUI

final class HistoryWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictation History"
        window.contentView = NSHostingView(rootView: HistoryView())
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct HistoryView: View {
    var embedded: Bool = false
    @State private var entries: [DictationHistoryEntry] = DictationCoordinator.shared.loadHistory()
    @State private var query: String = ""
    @State private var showClearConfirm = false

    private var filtered: [DictationHistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.finalText.lowercased().contains(q) ||
            ($0.destinationDisplayName?.lowercased().contains(q) ?? false)
        }
    }

    private var groups: [(title: String, entries: [DictationHistoryEntry])] {
        let calendar = Calendar.current
        var buckets: [Date: [DictationHistoryEntry]] = [:]
        for entry in filtered {
            let day = calendar.startOfDay(for: entry.timestamp)
            buckets[day, default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).map { day in
            (title: Self.dayTitle(day), entries: buckets[day] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !embedded {
                Text("Dictation History")
                    .font(.system(size: 18, weight: .semibold))
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search dictations", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                Spacer(minLength: 0)

                Button {
                    entries = DictationCoordinator.shared.loadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all history")
                .disabled(entries.isEmpty)
            }

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                                VStack(spacing: 8) {
                                    ForEach(group.entries) { entry in
                                        HistoryRow(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(embedded ? 0 : 20)
        .frame(minWidth: embedded ? 0 : 620, minHeight: embedded ? 320 : 460, alignment: .top)
        .mellotronThemed()
        .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                DictationCoordinator.shared.clearHistory()
                entries = []
            }
            Button("Cancel", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .preferencesDidChange)) { _ in
            entries = DictationCoordinator.shared.loadHistory()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "No history yet" : "No matches")
                .font(.system(size: 14, weight: .semibold))
            Text(query.isEmpty
                 ? "Your dictations show up here once you start talking. Turn on \u{201C}Save dictation history\u{201D} in General."
                 : "Try a different search term.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? "EEEE, MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: day)
    }
}

private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.mello)
                Text(entry.destinationDisplayName ?? "Current app")
                    .font(.system(size: 12.5, weight: .semibold))
                if !entry.pasteSucceeded {
                    Label("didn't paste", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Text(timeString(entry.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(entry.finalText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || copied ? 1 : 0)
                .help("Copy text")
            }

            Text(entry.finalText.isEmpty ? "(opened with no text)" : entry.finalText)
                .font(.system(size: 13))
                .foregroundStyle(entry.finalText.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
