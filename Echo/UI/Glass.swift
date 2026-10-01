import SwiftUI

enum GlassShape {
    case capsule, circle, rect(CGFloat)
}

struct Glassed: ViewModifier {
    var shape: GlassShape = .capsule
    var tint: Color = .clear
    var interactive: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            switch shape {
            case .capsule: content.glassEffect(variant, in: Capsule())
            case .circle: content.glassEffect(variant, in: Circle())
            case .rect(let r): content.glassEffect(variant, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            }
        } else {
            soft(content)
        }
        #else
        soft(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var variant: Glass {
        var g: Glass = tint == .clear ? .regular : .regular.tint(tint.opacity(0.18))
        if interactive { g = g.interactive() }
        return g
    }
    #endif

    @ViewBuilder
    private func soft<V: View>(_ v: V) -> some View {
        switch shape {
        case .capsule:
            v.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        case .circle:
            v.background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        case .rect(let r):
            let s = RoundedRectangle(cornerRadius: r, style: .continuous)
            v.background(.regularMaterial, in: s)
                .overlay(s.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        }
    }
}

extension View {
    func glass(_ shape: GlassShape = .capsule, tint: Color = .clear,
               interactive: Bool = true) -> some View {
        modifier(Glassed(shape: shape, tint: tint, interactive: interactive))
    }
}

struct GlassIconButton: View {
    let system: String
    var size: CGFloat = 44
    var hint: String = ""
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: { Notifier.shared.tap(); action() }) {
            Image(systemName: system)
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(active ? AnyShapeStyle(Color(hex: "D9483B")) : AnyShapeStyle(Color.primary))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(.circle)
        .accessibilityLabel(hint.isEmpty ? system : hint)
    }
}

struct GlassPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glass(.capsule)
    }
}

struct CircleFillButton: View {
    let system: String
    var diameter: CGFloat = 46
    var filled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: { Notifier.shared.tap(true); action() }) {
            Image(systemName: system)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Color.primary)
                .frame(width: diameter, height: diameter)
                .background(filled ? Color.black : Color(hex: "F2F2F5"), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct DividerLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.7)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.7)
        }
        .padding(.vertical, 6)
    }
}
