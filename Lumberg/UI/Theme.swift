import LumbergCore
import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x14120E)
    static let panel = Color(hex: 0x1D1A15)
    static let raised = Color(hex: 0x28241D)
    static let line = Color.white.opacity(0.08)
    static let paper = Color(hex: 0xEAE2CD)
    static let dim = Color(hex: 0xEAE2CD).opacity(0.55)
    static let faint = Color(hex: 0xEAE2CD).opacity(0.3)
    /// Swingline red.
    static let red = Color(hex: 0xE2402F)
    static let green = Color(hex: 0x9CCB8A)
    static let amber = Color(hex: 0xE3B158)
    static let blue = Color(hex: 0x7FA7C9)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(for kind: BlockKind) -> Color {
        switch kind {
        case .focus: return green
        case .shortBreak, .longBreak: return amber
        case .meeting: return blue
        }
    }

    static func color(for tag: WorkTag?) -> Color {
        guard let tag else { return dim }
        switch tag.colorName {
        case "green": return green
        case "red": return red
        case "amber": return amber
        default: return blue
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    init(hexString: String?) {
        let cleaned = (hexString ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(cleaned, radix: 16) ?? 0x7FA7C9)
    }
}

struct PillButton: ButtonStyle {
    var filled = false
    var tint: Color = Theme.red

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, filled: filled, tint: tint)
    }

    private struct Pill: View {
        let configuration: Configuration
        let filled: Bool
        let tint: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let lit = hovering && enabled
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(filled ? Color.white : Theme.paper)
                .background(filled ? tint : Theme.raised, in: Capsule())
                .overlay(Capsule().fill(Color.white.opacity(lit ? (filled ? 0.14 : 0.09) : 0)))
                .overlay(Capsule().strokeBorder(filled ? Color.clear : (lit ? Theme.paper.opacity(0.45) : Theme.line), lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : (enabled ? 1 : 0.4))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: lit)
        }
    }
}

/// For buttons that are only a symbol: a round highlight appears under the pointer.
struct IconButton: ButtonStyle {
    var size: CGFloat = 24
    var tint: Color = Theme.paper

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, size: size, tint: tint)
    }

    private struct Icon: View {
        let configuration: Configuration
        let size: CGFloat
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? tint : tint.opacity(0.6))
                .frame(width: size, height: size)
                .background(Color.white.opacity(hovering ? 0.12 : 0), in: Circle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A label that appears a moment after the pointer rests on something. Quicker than
/// the system tooltip, and styled to match.
struct Tip: ViewModifier {
    let text: String
    var above = false
    var align: HorizontalAlignment = .center
    @State private var shown = false
    @State private var pending: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    let work = DispatchWorkItem { shown = true }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                } else {
                    shown = false
                }
            }
            .overlay(alignment: Alignment(horizontal: align, vertical: above ? .top : .bottom)) {
                if shown {
                    Text(text)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.paper)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0x0B0A08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.paper.opacity(0.25), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        .fixedSize()
                        .alignmentGuide(above ? .top : .bottom) { d in above ? d[.bottom] + 7 : d[.top] - 7 }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: shown)
            .accessibilityHint(text)
    }
}

extension View {
    func tip(_ text: String, above: Bool = false, align: HorizontalAlignment = .center) -> some View {
        modifier(Tip(text: text, above: above, align: align))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.mono(10.5, .bold))
            .tracking(2.2)
            .foregroundStyle(Theme.dim)
    }
}

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    static let timeAMPM: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time.string(from: start))–\(timeAMPM.string(from: end))"
    }
}

/// The boss, in characters, sized to fill whatever height it is given.
struct AsciiBackdrop: View {
    var mood: Mood
    var animated = true

    private static let cols = 110, rows = 52
    private static let parts = AsciiPortrait.parts(cols: cols, rows: rows)
    private let cols = AsciiBackdrop.cols, rows = AsciiBackdrop.rows

    /// The portrait as text, with the suspenders, tie and mug picked out in colour.
    private func portrait(at time: Double) -> AttributedString {
        let lines = AsciiPortrait.render(cols: cols, rows: rows, mood: mood, time: time)
        var out = AttributedString()
        for (r, line) in lines.enumerated() {
            var run = "", current = AsciiPortrait.Part.plain
            func flush() {
                guard !run.isEmpty else { return }
                var piece = AttributedString(run)
                switch current {
                case .plain: break
                case .suspenders: piece.foregroundColor = Theme.red.opacity(0.8)
                case .tie: piece.foregroundColor = Theme.green.opacity(0.75)
                case .mug: piece.foregroundColor = Theme.paper.opacity(0.6)
                }
                out += piece
                run = ""
            }
            for (c, ch) in line.enumerated() {
                let part = ch == " " ? current : Self.parts[r][c]
                if part != current { flush(); current = part }
                run.append(ch)
            }
            flush()
            if r < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let size = max(4, min(geo.size.height / (CGFloat(rows) * 1.19), geo.size.width / (CGFloat(cols) * 0.602)))
            TimelineView(.periodic(from: .now, by: animated ? 0.3 : 3600)) { context in
                Text(portrait(at: context.date.timeIntervalSinceReferenceDate))
                    .font(.system(size: size, weight: .medium, design: .monospaced))
                    .lineSpacing(0)
                    .fixedSize()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
