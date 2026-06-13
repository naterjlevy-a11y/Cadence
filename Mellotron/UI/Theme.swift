import SwiftUI
import AppKit

// MARK: - Color

/// Mellotron palette. Anchored around a single warm purple ("mello"). Surfaces
/// are pure deep neutrals so the purple always pops. No gradients — flat colors
/// only, varied by opacity when we need depth.
extension Color {
    static let mello = Color(red: 0.72, green: 0.56, blue: 1.0)
    static let melloDeep = Color(red: 0.56, green: 0.42, blue: 0.92)
    static let melloSurface = Color(red: 0.13, green: 0.10, blue: 0.20)

    /// Near-black ink with the faintest purple shift. Use for app windows.
    static let melloInk = Color(red: 0.05, green: 0.04, blue: 0.08)
    /// Slightly lifted surface for cards on top of `melloInk`.
    static let melloMidnight = Color(red: 0.09, green: 0.08, blue: 0.13)
}

// MARK: - Typography

extension Font {
    static func melloDisplay(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size, relativeTo: .largeTitle)
    }

    static func melloDisplayItalic(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size, relativeTo: .largeTitle)
    }

    static func melloBody(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func melloMono(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Theme modifier

struct MellotronTheme: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(.mello)
    }
}

extension View {
    func mellotronThemed() -> some View {
        modifier(MellotronTheme())
    }
}

// MARK: - Display headline helper

struct DisplayHeadline: View {
    private let segments: [Segment]
    private let size: CGFloat
    private let tracking: CGFloat
    private let alignment: TextAlignment

    private enum Segment {
        case plain(String)
        case italic(String)
    }

    init(_ text: String, size: CGFloat = 34, tracking: CGFloat = -0.5, alignment: TextAlignment = .leading) {
        self.segments = [.plain(text)]
        self.size = size
        self.tracking = tracking
        self.alignment = alignment
    }

    private init(segments: [Segment], size: CGFloat, tracking: CGFloat, alignment: TextAlignment) {
        self.segments = segments
        self.size = size
        self.tracking = tracking
        self.alignment = alignment
    }

    func italic(_ text: String) -> DisplayHeadline {
        var next = segments
        next.append(.italic(text))
        return DisplayHeadline(segments: next, size: size, tracking: tracking, alignment: alignment)
    }

    var body: some View {
        segments.reduce(Text("")) { acc, segment in
            switch segment {
            case .plain(let s):
                return acc + Text(s).font(.melloDisplay(size))
            case .italic(let s):
                return acc + Text(s).font(.melloDisplayItalic(size))
            }
        }
        .tracking(tracking)
        .multilineTextAlignment(alignment)
        .foregroundStyle(.primary)
        .lineSpacing(2)
    }
}

// MARK: - Brand mark

/// Renders the bundled Mellotron app icon at any size. Use this everywhere the
/// app needs to identify itself visually — sign-in window header, settings
/// sidebar, menu bar popover header, onboarding, etc.
struct BrandMark: View {
    var size: CGFloat = 56
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let radius = cornerRadius ?? size * 0.22
        Group {
            if let nsImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.mello)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
