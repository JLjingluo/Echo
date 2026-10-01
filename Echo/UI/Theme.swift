import SwiftUI
import UIKit

enum EchoTheme {
    static func background(_ s: ColorScheme) -> Color { s == .dark ? .black : .white }
    static func primaryText(_ s: ColorScheme) -> Color { s == .dark ? .white : .black }
    static func secondaryText(_ s: ColorScheme) -> Color {
        s == .dark ? .white.opacity(0.66) : .black.opacity(0.58)
    }
    static func controlFill(_ s: ColorScheme) -> Color { s == .dark ? .white : .black }
    static func controlForeground(_ s: ColorScheme) -> Color { s == .dark ? .black : .white }
    static func controlStroke(_ s: ColorScheme) -> Color {
        s == .dark ? .white.opacity(0.22) : .black.opacity(0.14)
    }
    static func groupedFill(_ s: ColorScheme) -> Color {
        s == .dark ? .white.opacity(0.06) : .black.opacity(0.04)
    }
    static func selectionFill(_ s: ColorScheme) -> Color {
        s == .dark ? .white.opacity(0.20) : .black.opacity(0.10)
    }
    static func rowFill(_ s: ColorScheme) -> Color {
        s == .dark ? Color(white: 0.13) : Color(white: 0.94)
    }
    static func surface(_ s: ColorScheme) -> Color { s == .dark ? Color(white: 0.17) : .white }
}

enum EchoM {
    static let collapsedHInset: CGFloat = 32
    static let expandedHInset: CGFloat = 12
    static let maxContentWidth: CGFloat = 780
    static let readingWidth: CGFloat = 760
    static let timelineSpacing: CGFloat = 20
    static let blockSpacing: CGFloat = 12
    static let rowHeight: CGFloat = 42
    static let markerHeight: CGFloat = 32
    static let touch: CGFloat = 44
    static let diameter: CGFloat = 48
    static let sendDiameter: CGFloat = 36
    static let collapsedInset: CGFloat = 2
    static let collapsedRadius: CGFloat = 24
    static let expandedRadius: CGFloat = 26
    static let textInset: CGFloat = 16
    static let textToActions: CGFloat = 10
    static let expandedBottomInset: CGFloat = 8
    static let collapsedTextGap: CGFloat = 4
    static let drawerFraction: CGFloat = 0.75
    static let edgeActivation: CGFloat = 44
    static let closedScale: CGFloat = 0.95
    static let contentScrim: Double = 0.14
    static let sidebarVeil: Double = 0.5
    static let contentInset: CGFloat = 14
    static let sectionInset: CGFloat = 10
    static let surfaceRadius: CGFloat = 22
    static let cardRadius: CGFloat = 24
    static let codeRadius: CGFloat = 10
    static let bubbleRadius: CGFloat = 24
    static let editorMin: CGFloat = 72
    static let editorMax: CGFloat = 160
    static let footerClear: CGFloat = 82
    static let drawerSpring = Animation.interpolatingSpring(stiffness: 170, damping: 22)
}

enum EchoAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum EchoFont {
    private(set) static var hasCaveat = false

    static func register() {
        guard Bundle.main.url(forResource: "Caveat", withExtension: "ttf") != nil else { return }
        var registered = false
        if let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
           !urls.isEmpty {
            for u in urls {
                CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
            }
            registered = true
        }
        hasCaveat = registered
    }

    static func wordmark(_ size: CGFloat) -> Font {
        hasCaveat ? .custom("Caveat", fixedSize: size).weight(.medium)
            : .system(size: size, weight: .semibold, design: .rounded)
    }
}

struct EchoIcon: View {
    let name: String
    var size: CGFloat = 20
    var weight: Font.Weight = .regular

    init(_ name: String, size: CGFloat = 20, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
    }
}

struct ColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct EchoContentColumn: ViewModifier {
    var horizontalInset: CGFloat? = 24
    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let margin = horizontalInset ?? (containerWidth >= 414 ? 20 : 16)
        content
            .padding(.horizontal, margin)
            .padding(.top, 16)
            .frame(maxWidth: EchoM.readingWidth)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: ColumnWidthKey.self, value: g.size.width)
                }
            }
            .onPreferenceChange(ColumnWidthKey.self) { containerWidth = $0 }
    }
}

extension View {
    func echoColumn(_ inset: CGFloat? = 24) -> some View {
        modifier(EchoContentColumn(horizontalInset: inset))
    }
}

struct EchoSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: EchoM.surfaceRadius, style: .continuous)
                    .fill(EchoTheme.surface(scheme))
                    .opacity(reduceTransparency ? 1 : 0.92)
            }
    }
}

struct EchoGlassButton: View {
    enum Style { case regular, prominent }

    let title: String?
    let systemImage: String?
    var style: Style = .regular
    var role: ButtonRole?
    var isLoading = false
    var disabled = false
    var maxWidth: CGFloat? = .infinity
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(_ title: String, systemImage: String? = nil, style: Style = .regular,
         role: ButtonRole? = nil, isLoading: Bool = false, disabled: Bool = false,
         maxWidth: CGFloat? = .infinity, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.role = role
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = maxWidth
        self.action = action
    }

    init(systemImage: String, style: Style = .regular, isLoading: Bool = false,
         disabled: Bool = false, action: @escaping () -> Void) {
        self.title = nil
        self.systemImage = systemImage
        self.style = style
        self.role = nil
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = nil
        self.action = action
    }

    var body: some View {
        Group {
            if style == .prominent {
                Button(role: role, action: action) { label }
                    .buttonStyle(.plain)
                    .background {
                        if title == nil {
                            Circle().fill(EchoTheme.controlFill(scheme))
                        } else {
                            Capsule().fill(EchoTheme.controlFill(scheme))
                        }
                    }
            } else {
                Button(role: role, action: action) { label }
                    .buttonStyle(.plain)
                    .glass(title == nil ? .circle : .capsule, interactive: true)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(style == .prominent ? EchoTheme.controlForeground(scheme) : Color.primary)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .frame(maxWidth: maxWidth)
        .frame(minHeight: EchoM.touch)
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 10) {
            if let systemImage { EchoIcon(systemImage, size: 18) }
            if let title {
                Text(title).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .font(.body.weight(.semibold))
        .opacity(isLoading ? 0 : 1)
        .frame(maxWidth: title == nil ? EchoM.touch : nil)
        .frame(height: title == nil ? EchoM.touch : nil)
        .overlay {
            if isLoading {
                ProgressView().controlSize(.small)
                    .tint(style == .prominent ? EchoTheme.controlForeground(scheme) : .secondary)
            }
        }
    }
}
