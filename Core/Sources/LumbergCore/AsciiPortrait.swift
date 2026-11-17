import CoreGraphics
import Foundation

public enum Mood: String, Sendable {
    case neutral, pleased, displeased
}

/// Draws the boss as vector art into a grayscale bitmap, then samples it down
/// to a character grid. Drawing happens in a 100 x 94 unit space, origin top-left.
public enum AsciiPortrait {
    public static let fullView = CGRect(x: 0, y: 0, width: 100, height: 94)
    public static let faceView = CGRect(x: 29, y: 9, width: 42, height: 45)

    static let ramp: [Character] = Array(" .`:-~=+*cox#%8@")

    public static func render(
        cols: Int, rows: Int,
        view: CGRect = fullView,
        mood: Mood = .neutral,
        time: Double = 0
    ) -> [String] {
        let cellW = 3, cellH = 6
        let width = cols * cellW, height = rows * cellH
        guard cols > 0, rows > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / view.width, y: -CGFloat(height) / view.height)
        ctx.translateBy(x: -view.minX, y: -view.minY)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        draw(in: ctx, mood: mood, time: time)

        guard let data = ctx.data else { return [] }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var lines: [String] = []
        lines.reserveCapacity(rows)
        let top = Double(ramp.count - 1)
        for r in 0..<rows {
            var line = ""
            line.reserveCapacity(cols)
            for c in 0..<cols {
                var sum = 0
                for y in 0..<cellH {
                    let base = (r * cellH + y) * width + c * cellW
                    for x in 0..<cellW { sum += Int(pixels[base + x]) }
                }
                let v = Double(sum) / Double(cellW * cellH * 255)
                line.append(ramp[Int((v * top).rounded())])
            }
            lines.append(line)
        }
        return lines
    }

    // MARK: - Parts

    /// The pieces of the outfit worth colouring.
    public enum Part: Sendable {
        case plain, suspenders, tie, mug
    }

    /// Which part each character cell shows, for the same grid `render` produces.
    public static func parts(cols: Int, rows: Int, view: CGRect = fullView) -> [[Part]] {
        (0..<rows).map { r in
            (0..<cols).map { c in
                part(at: CGPoint(x: view.minX + (CGFloat(c) + 0.5) / CGFloat(cols) * view.width,
                                 y: view.minY + (CGFloat(r) + 0.5) / CGFloat(rows) * view.height))
            }
        }
    }

    /// Mirrors the paint order in `draw`: whatever is drawn last wins.
    static func part(at p: CGPoint) -> Part {
        // Hand, cuff and sleeve sit in front of everything on that side.
        if CGRect(x: 71.8, y: 68.6, width: 9.6, height: 9.6).contains(p) { return .plain }
        if inside(p, [(69.5, 77.4), (81.6, 79), (95, 95), (73, 95)]) { return .plain }
        if CGRect(x: 73.5, y: 61.2, width: 13, height: 16.8).contains(p) { return .mug }
        let dx = (p.x - 87.8) / 4.2, dy = (p.y - 70.1) / 5.5
        if dx * dx + dy * dy <= 1 { return .mug }
        if inside(p, [(48, 69), (52, 69), (56.5, 95), (43.5, 95)])
            || inside(p, [(46.6, 63.6), (53.4, 63.6), (52.2, 69.4), (47.8, 69.4)]) { return .tie }
        if inside(p, [(42.5, 55), (50, 65), (44.5, 71), (36, 61.5)])
            || inside(p, [(57.5, 55), (50, 65), (55.5, 71), (64, 61.5)]) { return .plain }
        for (a, b) in [(CGPoint(x: 35.5, y: 60.5), CGPoint(x: 30, y: 95)),
                       (CGPoint(x: 64.5, y: 60.5), CGPoint(x: 70, y: 95))] {
            guard p.y >= a.y else { continue }
            let t = (p.y - a.y) / (b.y - a.y)
            if abs(p.x - (a.x + (b.x - a.x) * t)) <= 2.5 { return .suspenders }
        }
        return .plain
    }

    private static func inside(_ p: CGPoint, _ pts: [(CGFloat, CGFloat)]) -> Bool {
        var hit = false
        var j = pts.count - 1
        for i in pts.indices {
            let (xi, yi) = pts[i], (xj, yj) = pts[j]
            if (yi > p.y) != (yj > p.y), p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi { hit.toggle() }
            j = i
        }
        return hit
    }

    // MARK: - Drawing

    private static func poly(_ ctx: CGContext, _ pts: [(CGFloat, CGFloat)], gray: CGFloat) {
        guard let first = pts.first else { return }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: first.0, y: first.1))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.closePath()
        ctx.setFillColor(gray: gray, alpha: 1)
        ctx.fillPath()
    }

    private static func line(_ ctx: CGContext, _ pts: [(CGFloat, CGFloat)], gray: CGFloat, width: CGFloat) {
        guard let first = pts.first else { return }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: first.0, y: first.1))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.setStrokeColor(gray: gray, alpha: 1)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    private static func ellipse(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, gray: CGFloat) {
        ctx.setFillColor(gray: gray, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func torsoPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 8, y: 94))
        p.addCurve(to: CGPoint(x: 38, y: 59), control1: CGPoint(x: 9, y: 70), control2: CGPoint(x: 22, y: 64))
        p.addLine(to: CGPoint(x: 62, y: 59))
        p.addCurve(to: CGPoint(x: 92, y: 94), control1: CGPoint(x: 78, y: 64), control2: CGPoint(x: 91, y: 70))
        p.closeSubpath()
        return p
    }

    private static func draw(in ctx: CGContext, mood: Mood, time: Double) {
        // Shirt, with pinstripes.
        let torso = torsoPath()
        ctx.addPath(torso)
        ctx.setFillColor(gray: 0.34, alpha: 1)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(torso)
        ctx.clip()
        var x: CGFloat = 9
        while x < 93 {
            line(ctx, [(x, 58), (x, 95)], gray: 0.5, width: 0.7)
            x += 3.2
        }
        ctx.restoreGState()

        // Suspenders.
        line(ctx, [(35.5, 60.5), (30, 95)], gray: 0.97, width: 4.6)
        line(ctx, [(64.5, 60.5), (70, 95)], gray: 0.97, width: 4.6)

        // Neck and the shadow under the chin.
        poly(ctx, [(43, 47), (57, 47), (58, 63), (42, 63)], gray: 0.6)
        ellipse(ctx, cx: 50, cy: 53.5, rx: 8, ry: 3.4, gray: 0.4)

        // Contrast collar.
        poly(ctx, [(42.5, 55), (50, 65), (44.5, 71), (36, 61.5)], gray: 1.0)
        poly(ctx, [(57.5, 55), (50, 65), (55.5, 71), (64, 61.5)], gray: 1.0)

        // Tie.
        let blade: [(CGFloat, CGFloat)] = [(48, 69), (52, 69), (56.5, 95), (43.5, 95)]
        poly(ctx, blade, gray: 0.72)
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 48, y: 69))
        for p in blade.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.closePath()
        ctx.clip()
        var y: CGFloat = 66
        while y < 100 {
            line(ctx, [(40, y + 6), (60, y - 4)], gray: 0.22, width: 1.3)
            y += 4.6
        }
        ctx.restoreGState()
        poly(ctx, [(46.6, 63.6), (53.4, 63.6), (52.2, 69.4), (47.8, 69.4)], gray: 0.86)

        // Ears.
        ellipse(ctx, cx: 34.6, cy: 36, rx: 2.3, ry: 4.2, gray: 0.58)
        ellipse(ctx, cx: 65.4, cy: 36, rx: 2.3, ry: 4.2, gray: 0.58)

        // Head.
        let head = CGRect(x: 35, y: 13.5, width: 30, height: 39.5)
        ctx.setFillColor(gray: 0.76, alpha: 1)
        ctx.fillEllipse(in: head)
        ctx.saveGState()
        ctx.addEllipse(in: head)
        ctx.clip()
        // Cheek shading on both sides.
        ellipse(ctx, cx: 34, cy: 40, rx: 4.5, ry: 14, gray: 0.6)
        ellipse(ctx, cx: 66, cy: 40, rx: 4.5, ry: 14, gray: 0.6)
        ctx.restoreGState()

        // Hair: dark cap with a side part and lighter strands.
        let hair = CGMutablePath()
        hair.move(to: CGPoint(x: 34.2, y: 31))
        hair.addCurve(to: CGPoint(x: 50, y: 11), control1: CGPoint(x: 32.5, y: 18), control2: CGPoint(x: 40, y: 11))
        hair.addCurve(to: CGPoint(x: 65.8, y: 31), control1: CGPoint(x: 60, y: 11), control2: CGPoint(x: 67.5, y: 18))
        hair.addLine(to: CGPoint(x: 63.4, y: 30))
        hair.addQuadCurve(to: CGPoint(x: 57, y: 20.5), control: CGPoint(x: 63.5, y: 22.5))
        hair.addQuadCurve(to: CGPoint(x: 44, y: 21.5), control: CGPoint(x: 50, y: 17.5))
        hair.addQuadCurve(to: CGPoint(x: 36.6, y: 30), control: CGPoint(x: 37, y: 23))
        hair.closeSubpath()
        ctx.addPath(hair)
        ctx.setFillColor(gray: 0.3, alpha: 1)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(hair)
        ctx.clip()
        for i in 0..<7 {
            let o = CGFloat(i) * 3.4
            line(ctx, [(41 + o, 11), (36 + o * 1.15, 24)], gray: 0.5, width: 0.8)
        }
        ctx.restoreGState()

        // Eyebrows.
        let inner: CGFloat, outer: CGFloat
        switch mood {
        case .neutral: inner = 27.6; outer = 27.9
        case .pleased: inner = 26.6; outer = 27.2
        case .displeased: inner = 28.8; outer = 26.6
        }
        line(ctx, [(38.4, outer), (47, inner)], gray: 0.16, width: 1.3)
        line(ctx, [(61.6, outer), (53, inner)], gray: 0.16, width: 1.3)

        // Glasses: big wire frames.
        for lx in [CGFloat(37.4), CGFloat(52.1)] {
            let lens = CGRect(x: lx, y: 29.4, width: 10.5, height: 9.2)
            let path = CGPath(roundedRect: lens, cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(gray: 0.5, alpha: 1)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(gray: 1.0, alpha: 1)
            ctx.setLineWidth(1.15)
            ctx.strokePath()
        }
        line(ctx, [(47.9, 32.4), (52.1, 32.4)], gray: 1.0, width: 1.0)
        line(ctx, [(37.4, 32), (34.4, 33.2)], gray: 1.0, width: 0.9)
        line(ctx, [(62.6, 32), (65.6, 33.2)], gray: 1.0, width: 0.9)

        // Eyes, half-lidded.
        for ex in [CGFloat(42.7), CGFloat(57.3)] {
            line(ctx, [(ex - 2.6, 33.3), (ex + 2.6, 33.3)], gray: 0.12, width: 0.9)
            ellipse(ctx, cx: ex, cy: 34.7, rx: 1.35, ry: 1.35, gray: 0.08)
        }

        // Nose.
        line(ctx, [(50.6, 36), (49, 42), (51.6, 42.8)], gray: 0.46, width: 0.9)

        // Mouth.
        let ctrlY: CGFloat, endY: CGFloat
        switch mood {
        case .neutral: ctrlY = 48.4; endY = 46.3
        case .pleased: ctrlY = 51; endY = 45.6
        case .displeased: ctrlY = 45.4; endY = 47.2
        }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 44.2, y: endY))
        ctx.addQuadCurve(to: CGPoint(x: 55.8, y: endY - 0.4), control: CGPoint(x: 50, y: ctrlY))
        ctx.setStrokeColor(gray: 0.16, alpha: 1)
        ctx.setLineWidth(1.15)
        ctx.strokePath()
        line(ctx, [(43.4, endY - 1.2), (44.2, endY)], gray: 0.4, width: 0.7)
        line(ctx, [(56.6, endY - 1.6), (55.8, endY - 0.4)], gray: 0.4, width: 0.7)

        // Sleeve, cuff, mug, hand.
        poly(ctx, [(69.5, 79), (81.5, 80.5), (95, 95), (73, 95)], gray: 0.42)
        poly(ctx, [(69.6, 77.4), (81.6, 79), (81.4, 82.4), (69.4, 80.6)], gray: 1.0)

        let mug = CGRect(x: 73.5, y: 62.5, width: 13, height: 15.5)
        ctx.setStrokeColor(gray: 0.9, alpha: 1)
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: CGRect(x: 84.6, y: 65.6, width: 6.4, height: 9))
        ctx.addPath(CGPath(roundedRect: mug, cornerWidth: 1.4, cornerHeight: 1.4, transform: nil))
        ctx.setFillColor(gray: 0.93, alpha: 1)
        ctx.fillPath()
        ellipse(ctx, cx: 80, cy: 62.6, rx: 6.5, ry: 1.5, gray: 1.0)
        ellipse(ctx, cx: 80, cy: 62.7, rx: 5.2, ry: 0.9, gray: 0.2)

        ctx.addPath(CGPath(roundedRect: CGRect(x: 71.8, y: 68.6, width: 9.6, height: 9.6),
                           cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.setFillColor(gray: 0.74, alpha: 1)
        ctx.fillPath()
        for fy in [CGFloat(71), CGFloat(73.4), CGFloat(75.8)] {
            line(ctx, [(72.6, fy), (80.4, fy)], gray: 0.42, width: 0.6)
        }

        // Steam, drifting with time.
        for (i, sx) in [CGFloat(76.6), CGFloat(80), CGFloat(83.4)].enumerated() {
            var prev: (CGFloat, CGFloat)? = nil
            let steps = 14
            for s in 0...steps {
                let f = CGFloat(s) / CGFloat(steps)
                let yy = 60.2 - f * 15
                let phase = Double(f) * 5.2 + time * 1.4 + Double(i) * 1.9
                let xx = sx + CGFloat(sin(phase)) * (0.6 + f * 1.8)
                if let p = prev {
                    line(ctx, [p, (xx, yy)], gray: 0.52 * (1 - f * 0.75), width: 0.85)
                }
                prev = (xx, yy)
            }
        }
    }
}
