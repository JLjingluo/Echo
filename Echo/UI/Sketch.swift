import SwiftUI

// MARK: - Palette

enum Ink {
    static let paper = Color(light: Color(rgba: 0xFDFDFBff), dark: Color(rgba: 0x141414ff))
    static let line = Color(light: Color(rgba: 0x1A1A1Aff), dark: Color(rgba: 0xEDEAE3ff))
    static let gray = Color(light: Color(rgba: 0x6E6E6Eff), dark: Color(rgba: 0xA8A5A0ff))
    static let faint = Color(light: Color(rgba: 0xB5B5B5ff), dark: Color(rgba: 0x6A6866ff))
    static let accent = Color(light: Color(rgba: 0x2B4FE0ff), dark: Color(rgba: 0x6B8CFFff))
    static let danger = Color(light: Color(rgba: 0xD93025ff), dark: Color(rgba: 0xFF8A80ff))
    static let wash = Color(light: Color(rgba: 0xF3F2EEff), dark: Color(rgba: 0x1C1C1Eff))
    static let blue = Color(light: Color(rgba: 0x2B4FE0ff), dark: Color(rgba: 0x6B8CFFff))
    static let red = Color(light: Color(rgba: 0xD93025ff), dark: Color(rgba: 0xFF8A80ff))
    static let green = Color(light: Color(rgba: 0x1A7F37ff), dark: Color(rgba: 0x56D364ff))
    static let soft = Color(light: Color(rgba: 0x6E6E6Eff), dark: Color(rgba: 0xA8A5A0ff))
}

enum Gutter {
    static let edge: CGFloat = 22
    static let stroke: CGFloat = 1.7
    static let strokeHeavy: CGFloat = 2.2
}

// MARK: - deterministic wobble

private func mix(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

private func wob(_ seed: UInt64, _ slot: Int, _ amp: CGFloat) -> CGFloat {
    let v = Double((mix(seed &+ UInt64(truncatingIfNeeded: slot)) >> 40)) / Double(1 << 24)
    return CGFloat(v * 2 - 1) * amp
}

private func sampled(_ base: Path, count: Int, seed: UInt64, amp: CGFloat) -> [CGPoint] {
    var pts: [CGPoint] = []
    pts.reserveCapacity(count)
    for i in 0..<count {
        let t = CGFloat(i) / CGFloat(count)
        if let p = base.trimmedPath(from: 0, to: max(t, 0.001)).currentPoint {
            pts.append(CGPoint(x: p.x + wob(seed, i * 2, amp), y: p.y + wob(seed, i * 2 + 1, amp)))
        }
    }
    return pts
}

private func closed(_ pts: [CGPoint], skip: Int? = nil) -> Path {
    var p = Path()
    guard pts.count > 3 else { return p }
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    p.move(to: mid(pts[0], pts[1]))
    for i in 1..<pts.count {
        let a = pts[i]
        let b = pts[(i + 1) % pts.count]
        if let s = skip, i % 4 == s { p.move(to: mid(a, b)) } else { p.addQuadCurve(to: mid(a, b), control: a) }
    }
    p.closeSubpath()
    return p
}

// MARK: - Shapes

struct SketchRect: Shape {
    var seed: UInt64 = 1
    var corner: CGFloat = 14
    var wobble: CGFloat = 1.3
    var gap: Int? = nil

    func path(in r: CGRect) -> Path {
        let rad = min(corner, min(r.width, r.height) / 2)
        let base = Path(roundedRect: r.insetBy(dx: 1.5, dy: 1.5),
                        cornerRadius: rad, style: .continuous)
        return closed(sampled(base, count: 22, seed: seed, amp: wobble), skip: gap)
    }
}

struct SketchCircle: Shape {
    var seed: UInt64 = 2
    var wobble: CGFloat = 1.2
    var open: Bool = true

    func path(in r: CGRect) -> Path {
        let base = Path(ellipseIn: r.insetBy(dx: 1.2, dy: 1.2))
        let pts = sampled(base, count: 20, seed: seed, amp: wobble)
        var p = Path()
        guard pts.count > 3 else { return p }
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        if !open { p.closeSubpath() }
        return p
    }
}

struct SketchCapsule: Shape {
    var seed: UInt64 = 3
    var wobble: CGFloat = 1.3
    var gap: Int? = nil

    func path(in r: CGRect) -> Path {
        let base = Path(roundedRect: r.insetBy(dx: 1.5, dy: 1.5),
                        cornerRadius: r.height / 2, style: .continuous)
        return closed(sampled(base, count: 26, seed: seed, amp: wobble), skip: gap)
    }
}

struct Hatch: Shape {
    var spacing: CGFloat = 7
    var inset: CGFloat = 5

    func path(in r: CGRect) -> Path {
        var p = Path()
        let box = r.insetBy(dx: inset, dy: inset)
        var x = box.minX - box.height
        while x < box.maxX {
            p.move(to: CGPoint(x: x, y: box.maxY))
            p.addLine(to: CGPoint(x: x + box.height, y: box.minY))
            x += spacing
        }
        return p
    }
}

// MARK: - Border modifier

struct SketchBorder: ViewModifier {
    var seed: UInt64 = 1
    var corner: CGFloat = 14
    var color: Color = Ink.line
    var width: CGFloat = Gutter.stroke
    var double = false
    var capsule = false
    var gap: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay { lines }
    }

    @ViewBuilder private var lines: some View {
        shape.stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        if double {
            shape.offset(x: 1.4, y: -1.1)
                .stroke(color.opacity(0.26),
                        style: StrokeStyle(lineWidth: width * 0.75, lineCap: .round))
        }
    }

    @ViewBuilder private var shape: some View {
        if capsule {
            SketchCapsule(seed: seed, gap: gap)
        } else {
            SketchRect(seed: seed, corner: corner, gap: gap)
        }
    }
}

extension View {
    func sketch(seed: UInt64 = 1, corner: CGFloat = 14, color: Color = Ink.line,
                width: CGFloat = Gutter.stroke, double: Bool = false,
                capsule: Bool = false, gap: Int? = nil) -> some View {
        modifier(SketchBorder(seed: seed, corner: corner, color: color, width: width,
                              double: double, capsule: capsule, gap: gap))
    }

    var paperBackground: some View {
        background(Ink.paper)
    }
}

// MARK: - Hand-drawn icons

enum HandGlyph: String, CaseIterable {
    case menu, plus, send, stop, chevron, check, close, folder, gear, mic, sparkle, ellipsis, search, doc, trash
}

struct HandIcon: View {
    let glyph: HandGlyph
    var size: CGFloat = 24
    var color: Color = Ink.line
    var seed: UInt64 = 5

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)
            let k = s / 24.0
            func ln(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat = 1.8, _ bend: CGFloat = 0.9) {
                var p = Path()
                p.move(to: a)
                let mx = (a.x + b.x) / 2 + wob(seed, Int(a.x * 7 + b.y * 13), bend * k)
                let my = (a.y + b.y) / 2 + wob(seed, Int(a.y * 11 + b.x * 3) &+ 50, bend * k)
                p.addQuadCurve(to: b, control: CGPoint(x: mx, y: my))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: w * k, lineCap: .round))
            }
            func dot(_ c: CGPoint, _ r: CGFloat) {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            switch glyph {
            case .menu:
                ln(pt(3, 7), pt(21, 6.6), 1.9)
                ln(pt(3.4, 12), pt(20.6, 12.4), 1.9)
                ln(pt(4, 17.4), pt(16, 17), 1.9)
            case .plus:
                ln(pt(12, 3.5), pt(11.6, 21), 2.0, 1.2)
                ln(pt(3.8, 12.4), pt(20.4, 11.8), 2.0, 1.2)
            case .send:
                ln(pt(12, 21), pt(12.2, 3.6), 2.0)
                ln(pt(5.4, 10.2), pt(12.2, 3.4), 2.0)
                ln(pt(12.2, 3.4), pt(18.8, 10.6), 2.0)
                ln(pt(12.2, 21), pt(15.4, 18.2), 1.5, 1.4)
            case .stop:
                let r = CGRect(x: 7.5 * k, y: 7.5 * k, width: 9 * k, height: 9 * k)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.8 * k), with: .color(color))
            case .chevron:
                ln(pt(6.5, 9.5), pt(12, 15), 1.9)
                ln(pt(12, 15), pt(17.6, 9.3), 1.9)
            case .check:
                ln(pt(4.5, 12.8), pt(9.5, 17.6), 2.1)
                ln(pt(9.5, 17.6), pt(20, 5.8), 2.1)
            case .close:
                ln(pt(5.5, 5.5), pt(18.8, 19), 1.9)
                ln(pt(18.6, 5.2), pt(5.2, 18.6), 1.9)
            case .folder:
                ln(pt(3, 8), pt(9, 7.6), 1.8)
                ln(pt(9, 7.6), pt(11, 10.4), 1.8)
                ln(pt(11, 10.4), pt(21, 10), 1.8)
                ln(pt(21, 10), pt(20.4, 19.6), 1.8)
                ln(pt(20.4, 19.6), pt(3.4, 20), 1.8)
                ln(pt(3.4, 20), pt(3, 8), 1.8)
            case .gear:
                let c = pt(12, 12)
                let ring = CGRect(x: c.x - 5.4 * k, y: c.y - 5.4 * k, width: 10.8 * k, height: 10.8 * k)
                ctx.stroke(Path(ellipseIn: ring), with: .color(color),
                           style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round))
                for i in 0..<6 {
                    let a = Double(i) / 6.0 * Double.pi * 2
                    ln(pt(12 + cos(a) * 6.6, 12 + sin(a) * 6.6),
                       pt(12 + cos(a) * 9.4, 12 + sin(a) * 9.4), 1.7)
                }
            case .mic:
                ln(pt(12, 4), pt(12, 13), 3.2, 0.5)
                ln(pt(6.5, 12), pt(6.8, 15.5), 1.8)
                ln(pt(6.8, 15.5), pt(17.4, 15.2), 1.8)
                ln(pt(17.4, 15.2), pt(17.6, 11.8), 1.8)
                ln(pt(12, 18.6), pt(12, 21), 1.8)
            case .sparkle:
                ln(pt(12, 3.5), pt(12.4, 20.5), 1.9)
                ln(pt(4, 11.4), pt(20.2, 12), 1.9)
                ln(pt(6.6, 6), pt(17.4, 17.6), 1.5)
                ln(pt(17.6, 6.4), pt(6.4, 17.4), 1.5)
            case .ellipsis:
                dot(pt(5.5, 12.2), 1.5 * k)
                dot(pt(12, 11.8), 1.5 * k)
                dot(pt(18.5, 12.3), 1.5 * k)
            case .search:
                let c = pt(10.4, 10.4)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 5.2 * k, y: c.y - 5.2 * k,
                                                  width: 10.4 * k, height: 10.4 * k)),
                           with: .color(color), style: StrokeStyle(lineWidth: 1.8 * k))
                ln(pt(14.6, 14.8), pt(20.4, 20.6), 2.0)
            case .doc:
                ln(pt(6, 3.4), pt(15, 3.2), 1.8)
                ln(pt(15, 3.2), pt(18.6, 7), 1.8)
                ln(pt(18.6, 7), pt(18.2, 20.6), 1.8)
                ln(pt(18.2, 20.6), pt(6.2, 20.2), 1.8)
                ln(pt(6.2, 20.2), pt(6, 3.4), 1.8)
                ln(pt(9, 11), pt(15.6, 10.8), 1.4)
                ln(pt(9, 15), pt(15.6, 14.7), 1.4)
            case .trash:
                ln(pt(4.5, 7), pt(19.5, 6.8), 1.9)
                ln(pt(9.5, 4.4), pt(14.5, 4.2), 1.7)
                ln(pt(6.4, 7.2), pt(7.6, 20.4), 1.8)
                ln(pt(17.6, 7), pt(16.6, 20.2), 1.8)
                ln(pt(7.6, 20.4), pt(16.6, 20.2), 1.8)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Brand figure

struct BrandFace: View {
    var size: CGFloat = 72
    var seed: UInt64 = 91
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5.3)) { _ in
            Canvas { ctx, sz in
                let k = min(sz.width, sz.height) / 24.0
                let box = CGRect(x: 2 * k, y: 2 * k, width: 20 * k, height: 20 * k)
                ctx.stroke(SketchCircle(seed: seed).path(in: box), with: .color(Ink.line),
                           style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round))
                func eye(_ x: CGFloat, _ accent: Bool) {
                    if blink && accent {
                        var p = Path()
                        p.move(to: CGPoint(x: x * k, y: 10.4 * k))
                        p.addLine(to: CGPoint(x: (x + 2.4) * k, y: 10.5 * k))
                        ctx.stroke(p, with: .color(Ink.line),
                                   style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round))
                    } else {
                        let r = (accent ? 1.5 : 1.2) * k
                        ctx.fill(Path(ellipseIn: CGRect(x: (x + 0.6) * k - r, y: 10.2 * k - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(accent ? Ink.accent : Ink.line))
                    }
                }
                eye(8, false)
                eye(14, true)
                var mouth = Path()
                mouth.move(to: CGPoint(x: 9 * k, y: 15 * k))
                mouth.addQuadCurve(to: CGPoint(x: 15.4 * k, y: 14.6 * k),
                                   control: CGPoint(x: 12.2 * k, y: 17.4 * k))
                ctx.stroke(mouth, with: .color(Ink.line),
                           style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round))
            }
            .frame(width: size, height: size)
            .onChange(of: blink) { _, _ in }
            .task(id: Date()) {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(120))
                blink = false
            }
            .onAppear { schedule() }
        }
        .accessibilityHidden(true)
    }

    private func schedule() {
        guard !reduceMotion else { return }
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(4000 + Int.random(in: 0...3000)))
                withAnimation(.easeOut(duration: 0.09)) { blink = true }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.12)) { blink = false }
            }
        }
    }
}

// MARK: - Fonts

enum Hand {
    static func pencil(_ size: CGFloat) -> Font {
        EchoFont.hasCaveat ? .custom("Caveat", fixedSize: size).weight(.semibold)
            : .system(size: size, weight: .medium, design: .rounded)
    }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 13) -> Font { .system(size: size, design: .monospaced) }
}

// MARK: - Mono tech line with a crooked underline

struct TechLabel: View {
    let text: String
    var size: CGFloat = 13
    var chevron = true

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text(text)
                .font(Hand.mono(size))
                .foregroundStyle(Ink.gray)
                .lineLimit(1)
                .truncationMode(.middle)
            if chevron {
                HandIcon(glyph: .chevron, size: 11, color: Ink.faint, seed: 13)
            }
        }
        .overlay(alignment: .bottom) {
            SketchRect(seed: 77, corner: 2, wobble: 1.0)
                .stroke(Ink.faint, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                .offset(x: -3, y: 3)
        }
    }
}
