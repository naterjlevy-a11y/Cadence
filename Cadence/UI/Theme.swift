import SwiftUI
import AppKit

// MARK: - Color

/// Cadence palette — "Ink + Glacier Blue", matching the landing page exactly.
/// One glacier accent over deep cool neutrals. Flat colors only; depth comes
/// from the token opacities below, never from ad-hoc `.opacity(…)` sprinkles.
extension Color {
    /// Glacier — #7c9cff. The one accent.
    static let mello = Color(red: 0.486, green: 0.612, blue: 1.0)
    /// Deep glacier — #5c7ce0. Pressed states.
    static let melloDeep = Color(red: 0.361, green: 0.486, blue: 0.878)
    /// Surface — #141821. Pills, cards, popovers.
    static let melloSurface = Color(red: 0.078, green: 0.094, blue: 0.129)
    /// Near-black ink — #0b0d12. App windows.
    static let melloInk = Color(red: 0.043, green: 0.051, blue: 0.071)
    /// Lifted card surface on ink — #12161f.
    static let melloMidnight = Color(red: 0.070, green: 0.086, blue: 0.121)

    // ── Semantic tokens (use these, not raw opacities) ──
    /// Card fill on a window background.
    static let surfaceCard = Color.white.opacity(0.035)
    /// Hovered row / control fill.
    static let surfaceHover = Color.white.opacity(0.07)
    /// Hairline strokes around cards and separators.
    static let strokeHairline = Color.white.opacity(0.09)
    /// Primary text.
    static let textPrimary = Color.white.opacity(0.94)
    /// Secondary text — one-line row subtitles, values.
    static let textSecondary = Color.white.opacity(0.55)
    /// Tertiary text — timestamps, footnotes.
    static let textTertiary = Color.white.opacity(0.35)
}

// MARK: - Typography (Inter everywhere; mono only for keys/codes/stats)

extension Font {
    /// Pane titles, dialog headlines.
    static func cadTitle(_ size: CGFloat = 22) -> Font {
        .custom("Inter-SemiBold", size: size, relativeTo: .title2)
    }

    /// Emphasized labels, buttons, row titles that need weight.
    static func cadMedium(_ size: CGFloat = 13) -> Font {
        .custom("Inter-Medium", size: size, relativeTo: .body)
    }

    /// Body copy, row labels.
    static func cadBody(_ size: CGFloat = 13) -> Font {
        .custom("Inter-Regular", size: size, relativeTo: .body)
    }

    /// Small section headers. Sentence case, semibold, secondary color —
    /// never uppercase mono walls.
    static func cadLabel(_ size: CGFloat = 11) -> Font {
        .custom("Inter-SemiBold", size: size, relativeTo: .caption)
    }

    /// Keyboard keys, OTP codes, stats. SF Mono.
    static func cadMono(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // ── Legacy shims (old call sites resolve to Inter until each surface is
    //    rewritten; keeps the app compiling during the migration) ──
    static func melloDisplay(_ size: CGFloat) -> Font { .cadTitle(size * 0.82) }
    static func melloDisplayItalic(_ size: CGFloat) -> Font { .cadTitle(size * 0.82) }
    static func melloBody(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        weight == .regular ? .cadBody(size) : .cadMedium(size)
    }
    static func melloMono(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .cadMono(size, weight: weight)
    }
}

// MARK: - Theme modifier

struct CadenceTheme: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(.mello)
    }
}

extension View {
    func cadenceThemed() -> some View {
        modifier(CadenceTheme())
    }
}

// MARK: - Display headline helper (legacy shim — renders Inter now)

struct DisplayHeadline: View {
    private let parts: [(String, Bool)]
    private let size: CGFloat
    private let alignment: TextAlignment

    init(_ text: String, size: CGFloat = 34, tracking: CGFloat = 0, alignment: TextAlignment = .leading) {
        self.parts = [(text, false)]
        self.size = size
        self.alignment = alignment
    }

    private init(parts: [(String, Bool)], size: CGFloat, alignment: TextAlignment) {
        self.parts = parts
        self.size = size
        self.alignment = alignment
    }

    func italic(_ text: String) -> DisplayHeadline {
        DisplayHeadline(parts: parts + [(text, true)], size: size, alignment: alignment)
    }

    var body: some View {
        Text(parts.map(\.0).joined())
            .font(.cadTitle(size * 0.78))
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(alignment)
            .lineSpacing(2)
    }
}

// MARK: - Brand mark

/// The Cadence pill mark, drawn as a native vector — crisp at every size,
/// identical everywhere: settings sidebar, popover, onboarding, sign-in,
/// paywall. `boxed: true` wraps it in the dark app-icon square.
struct BrandMark: View {
    var size: CGFloat = 56
    var cornerRadius: CGFloat? = nil
    var boxed: Bool = true

    var body: some View {
        let radius = cornerRadius ?? size * 0.22
        ZStack {
            if boxed {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.melloSurface, Color.melloInk],
                                         startPoint: .top, endPoint: .bottom))
            }
            PillMark()
                .frame(width: size * (boxed ? 0.68 : 1.0),
                       height: size * (boxed ? 0.29 : 0.42))
        }
        .frame(width: size, height: boxed ? size : size * 0.42)
    }
}

/// The pill itself: glacier stadium + white waveform pulse.
struct PillMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Capsule().fill(Color.mello)
                WaveformGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.5, h * 0.115), lineCap: .round))
                    .frame(width: w * 0.62, height: h * 0.58)
            }
        }
        .aspectRatio(240 / 100, contentMode: .fit)
    }
}

/// Normalized waveform path (matches brand/cadence-logo.svg).
struct WaveformGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // x positions and half-heights as fractions of the glyph box
        let bars: [(x: CGFloat, half: CGFloat)] = [
            (0.00, 0.0), (0.17, 0.5), (0.36, 1.0), (0.55, 0.17), (0.74, 0.67), (0.92, 0.0), (1.0, 0.33),
        ]
        let midY = rect.midY
        for b in bars {
            let x = rect.minX + b.x * rect.width
            if b.half == 0 {
                p.move(to: CGPoint(x: x, y: midY - 0.01))
                p.addLine(to: CGPoint(x: x, y: midY + 0.01))
            } else {
                let dy = b.half * rect.height / 2
                p.move(to: CGPoint(x: x, y: midY - dy))
                p.addLine(to: CGPoint(x: x, y: midY + dy))
            }
        }
        return p
    }
}
