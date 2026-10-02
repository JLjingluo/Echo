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
            let spike = (mix(seed &+ UInt64(truncatingIfNeeded: i)) % 13) == 0 ? 2.6 : 1
            pts.append(CGPoint(x: p.x + wob(seed, i * 2, amp * CGFloat(spike)),
                               y: p.y + wob(seed, i * 2 + 1, amp * CGFloat(spike))))
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
    var wobble: CGFloat = 0.5
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
    var wobble: CGFloat = 0.45
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
    var wobble: CGFloat = 0.5
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

// MARK: - Rough box: four strokes that overshoot their corners

struct SketchBox: Shape {
    var seed: UInt64 = 1
    var wobble: CGFloat = 0.45
    var overshoot: CGFloat = 1.6
    var gapSide: Int? = nil

    func path(in r: CGRect) -> Path {
        let b = r.insetBy(dx: 2, dy: 2)
        func j(_ i: Int) -> CGFloat { wob(seed, i, wobble) }
        var p = Path()
        let corners = [
            CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
            CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY),
        ]
        for side in 0..<4 {
            if gapSide == side { continue }
            let a = corners[side]
            let c = corners[(side + 1) % 4]
            let dx = c.x - a.x, dy = c.y - a.y
            let len = max(1, hypot(dx, dy))
            let ux = dx / len, uy = dy / len
            let start = CGPoint(x: a.x - ux * overshoot + j(side * 5),
                                y: a.y - uy * overshoot + j(side * 5 + 1))
            let end = CGPoint(x: c.x + ux * overshoot + j(side * 5 + 2),
                              y: c.y + uy * overshoot + j(side * 5 + 3))
            let mid = CGPoint(x: (start.x + end.x) / 2 + j(side * 5 + 4) * 1.0,
                              y: (start.y + end.y) / 2 + j(side * 5 + 9) * 1.0)
            p.move(to: start)
            p.addQuadCurve(to: end, control: mid)
        }
        return p
    }
}

// MARK: - Animatable trim so a line can be "redrawn"

struct TrimmedShape<S: Shape>: Shape {
    var shape: S
    var progress: CGFloat = 1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let full = shape.path(in: rect)
        guard progress < 0.999 else { return full }
        return full.trimmedPath(from: 0, to: max(0.001, progress))
    }
}

struct RedrawStroke<S: Shape>: View {
    var shape: S
    var color: Color = Ink.line
    var width: CGFloat = Gutter.stroke
    var progress: CGFloat = 1

    var body: some View {
        TrimmedShape(shape: shape, progress: progress)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Press = re-stroke the outline

struct RedrawButtonStyle<S: Shape>: ButtonStyle {
    var shape: S
    var color: Color = Ink.line
    var width: CGFloat = Gutter.stroke
    var fill: Color = .clear
    var double = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        PressLabel(configuration)
            .background(fill)
            .overlay {
                RedrawStroke(shape: shape, color: color, width: width,
                             progress: configuration.isPressed ? 0.999 : 1)
                if double {
                    RedrawStroke(shape: shape, color: color.opacity(0.26), width: width * 0.75,
                                 progress: configuration.isPressed ? 0.94 : 1)
                        .offset(x: 1.4, y: -1.1)
                }
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.01 : 0.15),
                       value: configuration.isPressed)
    }
}

private struct PressLabel: View {
    let configuration: ButtonStyleConfiguration
    init(_ c: ButtonStyleConfiguration) { configuration = c }
    var body: some View { configuration.label }
}

// MARK: - Paper grain

struct PaperGrain: View {
    var density: Int = 900
    var opacity: Double = 0.035
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, sz in
            var s: UInt64 = 0x5EED
            for _ in 0..<density {
                s = mix(s)
                let x = CGFloat(s & 0xFFFF) / 65535 * sz.width
                let y = CGFloat((s >> 16) & 0xFFFF) / 65535 * sz.height
                let r = 0.35 + CGFloat((s >> 32) & 0xFF) / 255 * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(scheme == .dark ? Color.white : Color.black))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Ink breathing on the accent dot

struct InkDot: View {
    var size: CGFloat = 7
    var color: Color = Ink.accent
    var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bleed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: breathing && !reduceMotion && bleed ? 0.9 : 0)
            .scaleEffect(breathing && !reduceMotion && bleed ? 1.25 : 1)
            .task(id: breathing) {
                guard breathing, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 6000...11000)))
                    withAnimation(.easeInOut(duration: 0.09)) { bleed = true }
                    try? await Task.sleep(for: .milliseconds(90))
                    withAnimation(.easeInOut(duration: 0.16)) { bleed = false }
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Border modifier

struct SketchBorder: ViewModifier {
    var seed: UInt64 = 1
    var corner: CGFloat = 14
    var capsule = false
    var color: Color = Ink.line
    var width: CGFloat = Gutter.stroke
    var double = false
    var gap: Int? = nil

    func body(content: Content) -> some View {
        content.overlay {
            strokeShape(offset: .zero, opacity: 1, scale: 1)
            if double {
                strokeShape(offset: CGSize(width: 1.4, height: -1.1), opacity: 0.26, scale: 0.75)
            }
        }
    }

    @ViewBuilder
    private func strokeShape(offset: CGSize, opacity: Double, scale: CGFloat) -> some View {
        let style = StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
        if capsule {
            SketchCapsule(seed: seed, gap: gap)
                .stroke(color.opacity(opacity), style: style)
                .offset(offset)
        } else {
            SketchRect(seed: seed, corner: corner, gap: gap)
                .stroke(color.opacity(opacity), style: style)
                .offset(offset)
        }
    }
}

extension View {
    func sketch(seed: UInt64 = 1, corner: CGFloat = 14, capsule: Bool = false,
                color: Color = Ink.line, width: CGFloat = Gutter.stroke,
                double: Bool = false, gap: Int? = nil) -> some View {
        modifier(SketchBorder(seed: seed, corner: corner, capsule: capsule, color: color,
                              width: width, double: double, gap: gap))
    }

    var paperBackground: some View {
        background(Ink.paper)
    }
}

struct BoxBorder: ViewModifier {
    var seed: UInt64 = 1
    var color: Color = Ink.line
    var width: CGFloat = Gutter.stroke
    var double = true
    var gapSide: Int? = nil

    func body(content: Content) -> some View {
        content.overlay {
            SketchBox(seed: seed, gapSide: gapSide)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            if double {
                SketchBox(seed: seed &+ 9, wobble: 0.6, overshoot: 1.2, gapSide: gapSide)
                    .stroke(color.opacity(0.22),
                            style: StrokeStyle(lineWidth: width * 0.7, lineCap: .round))
                    .offset(x: 1.3, y: -1.0)
            }
        }
    }
}

extension View {
    func sketchBox(seed: UInt64 = 1, color: Color = Ink.line, width: CGFloat = Gutter.stroke,
                   double: Bool = true, gapSide: Int? = nil) -> some View {
        modifier(BoxBorder(seed: seed, color: color, width: width, double: double,
                           gapSide: gapSide))
    }
}

// MARK: - Composite hand-drawn controls

struct HandToggle: View {
    @Binding var isOn: Bool
    var seed: UInt64 = 700

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
            Notifier.shared.tap()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                SketchCapsule(seed: seed)
                    .stroke(isOn ? Ink.accent : Ink.faint,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                if isOn {
                    Hatch(spacing: 6, inset: 4)
                        .stroke(Ink.accent.opacity(0.25), lineWidth: 1)
                        .clipShape(Capsule())
                }
                SketchCircle(seed: seed &+ 3, open: false)
                    .fill(isOn ? Ink.accent : Ink.paper)
                    .overlay(SketchCircle(seed: seed &+ 3, open: false)
                        .stroke(isOn ? Ink.accent : Ink.gray, lineWidth: 1.5))
                    .padding(3)
                    .frame(width: 26, height: 26)
            }
            .frame(width: 52, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

struct HandSegmented: View {
    let options: [(label: String, value: String)]
    @Binding var selection: String
    var seed: UInt64 = 710

    var body: some View {
        HStack(spacing: 14) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = o.value }
                } label: {
                    Text(o.label)
                        .font(Hand.body(15).weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Ink.line : Ink.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay {
                            if on {
                                SketchRect(seed: seed &+ UInt64(o.value.hash & 255),
                                           corner: 12, wobble: 0.9)
                                    .stroke(Ink.accent,
                                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                                    .padding(-2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HandCounter: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Hand.body(16)).foregroundStyle(Ink.line)
            Spacer()
            stepButton(-1)
            Text("\(value)\(unit)")
                .font(Hand.mono(15))
                .foregroundStyle(Ink.line)
                .frame(minWidth: 44)
            stepButton(1)
        }
        .frame(minHeight: 46)
    }

    private func stepButton(_ d: Int) -> some View {
        Button {
            let next = value + d * step
            guard range.contains(next) else { return }
            withAnimation(.easeOut(duration: 0.12)) { value = next }
        } label: {
            HandIcon(glyph: d < 0 ? .close : .plus, size: 13,
                     color: range.contains(value + d * step) ? Ink.line : Ink.faint,
                     seed: UInt64(720 + d))
                .rotationEffect(.degrees(d < 0 ? 45 : 0))
                .frame(width: 30, height: 30)
                .overlay(SketchCircle(seed: UInt64(730 + d))
                    .stroke(range.contains(value + d * step) ? Ink.line : Ink.faint,
                            lineWidth: 1.4))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!range.contains(value + d * step))
    }
}

struct HandRow: View {
    let glyph: HandGlyph
    let title: String
    var value: String = ""
    var valueAccent = false
    var divider = true
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HandIcon(glyph: glyph, size: 19, color: Ink.gray, seed: 741)
                    .frame(width: 24)
                Text(title)
                    .font(Hand.body(16))
                    .foregroundStyle(Ink.line)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(Hand.mono(13))
                        .foregroundStyle(valueAccent ? Ink.accent : Ink.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if action != nil {
                    HandIcon(glyph: .chevron, size: 12, color: Ink.faint, seed: 742)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(minHeight: 50)
            if divider {
                SketchRect(seed: 743, corner: 1, wobble: 0.6)
                    .stroke(Ink.faint.opacity(0.4), lineWidth: 1)
                    .frame(height: 1)
                    .padding(.leading, 36)
            }
        }
        .contentShape(Rectangle())
    }
}

struct HandSectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Hand.pencil(19))
            .foregroundStyle(Ink.faint)
            .padding(.top, 22)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HandSearchField: View {
    @Binding var text: String
    var prompt: String = "搜"

    var body: some View {
        HStack(spacing: 8) {
            HandIcon(glyph: .search, size: 16, color: Ink.gray, seed: 751)
            TextField(prompt, text: $text)
                .font(Hand.body(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    HandIcon(glyph: .close, size: 12, color: Ink.gray, seed: 752)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .sketch(seed: 753, capsule: true, color: Ink.faint, width: 1.3)
    }
}

extension View {
    func handSheet(title: String) -> some View {
        self
            .background(Ink.paper.ignoresSafeArea())
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    SketchRect(seed: 761, corner: 2, wobble: 0.8)
                        .stroke(Ink.faint, lineWidth: 2)
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                    Text(title)
                        .font(Hand.display(22))
                        .foregroundStyle(Ink.line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Gutter.edge)
                }
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 58) }
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

    static func auto(_ s: String, _ size: CGFloat) -> Font {
        s.allSatisfy { $0.isASCII && !$0.isWhitespace } ? pencil(size + 3) : body(size)
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
            SketchRect(seed: 77, corner: 2, wobble: 0.5)
                .stroke(Ink.faint, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                .offset(x: -3, y: 3)
        }
    }
}
