import AppKit
import SwiftUI

enum WindowMetrics {
    static let cornerRadius: CGFloat = 18
}

struct ClipFlowTheme {
    let scheme: ColorScheme

    var lightWindowBackground: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 229.0 / 255.0, green: 250.0 / 255.0, blue: 255.0 / 255.0),
                    location: 0
                ),
                .init(
                    color: Color(red: 243.0 / 255.0, green: 250.0 / 255.0, blue: 255.0 / 255.0),
                    location: 0.43
                ),
                .init(
                    color: Color(red: 249.0 / 255.0, green: 250.0 / 255.0, blue: 251.0 / 255.0),
                    location: 1
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var foreground: Color { scheme == .dark ? oklch(0.97, 0.004, 260) : oklch(0.22, 0.01, 265) }
    var foregroundSecondary: Color { scheme == .dark ? oklch(0.84, 0.008, 260) : oklch(0.34, 0.01, 265) }
    var muted: Color { scheme == .dark ? oklch(0.72, 0.012, 260) : oklch(0.48, 0.012, 265) }
    var accent: Color { scheme == .dark ? oklch(0.74, 0.13, 218) : oklch(0.56, 0.14, 218) }
    var danger: Color { oklch(0.70, 0.17, 25) }
    var star: Color { oklch(0.83, 0.15, 85) }

    var glass: Color {
        scheme == .dark ? oklch(0.24, 0.022, 265, 0.58) : oklch(0.96, 0.004, 265, 0.62)
    }
    var glassSecondary: Color {
        scheme == .dark ? oklch(0.20, 0.02, 265, 0.42) : oklch(0.91, 0.006, 265, 0.48)
    }
    var chip: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.08) }
    var chipHigh: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.14) }
    var hairline: Color { (scheme == .dark ? Color.white : Color.black).opacity(scheme == .dark ? 0.08 : 0.10) }
    var weakHairline: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.045) }
    var selection: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.13) }
    var skeleton: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.07) }
    var skeletonHigh: Color { (scheme == .dark ? Color.white : Color.black).opacity(0.13) }

    private func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, _ alpha: Double = 1) -> Color {
        Color(Self.nsColor(lightness: lightness, chroma: chroma, hue: hue, alpha: alpha))
    }

    private static func nsColor(lightness: Double, chroma: Double, hue: Double, alpha: Double) -> NSColor {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)

        let lPrime = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = lightness - 0.0894841775 * a - 1.2914855480 * b

        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime

        let linearRed = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let linearGreen = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let linearBlue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        func gamma(_ value: Double) -> Double {
            let converted = value <= 0.0031308
                ? 12.92 * value
                : 1.055 * pow(value, 1 / 2.4) - 0.055
            return min(1, max(0, converted))
        }

        return NSColor(
            srgbRed: gamma(linearRed),
            green: gamma(linearGreen),
            blue: gamma(linearBlue),
            alpha: alpha
        )
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

struct KeyCap: View {
    let text: String
    var muted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(muted ? theme.muted : theme.foregroundSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(theme.chip)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct GlassButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger }
    let kind: Kind
    let horizontalPadding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    init(kind: Kind, horizontalPadding: CGFloat = 8) {
        self.kind = kind
        self.horizontalPadding = horizontalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(
            configuration: configuration,
            kind: kind,
            horizontalPadding: horizontalPadding,
            colorScheme: colorScheme
        )
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: GlassButtonStyle.Kind
    let horizontalPadding: CGFloat
    let colorScheme: ColorScheme
    @State private var hovering = false

    var body: some View {
        let theme = ClipFlowTheme(scheme: colorScheme)
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(foreground(theme: theme))
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, horizontalPadding)
            .background(background(theme: theme))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(border(theme: theme), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
    }

    private func background(theme: ClipFlowTheme) -> Color {
        if configuration.isPressed { return (colorScheme == .dark ? Color.white : Color.black).opacity(0.20) }
        switch kind {
        case .normal: return hovering ? theme.chipHigh : theme.chip
        case .primary: return theme.accent.opacity(hovering ? 0.34 : 0.22)
        case .danger: return hovering ? theme.danger.opacity(0.16) : theme.chip
        }
    }

    private func foreground(theme: ClipFlowTheme) -> Color {
        if isDanger && hovering { return theme.danger.opacity(0.95) }
        return isDanger ? theme.foregroundSecondary : theme.foreground
    }

    private var isDanger: Bool {
        if case .danger = kind { return true }
        return false
    }

    private func border(theme: ClipFlowTheme) -> Color {
        kind == .primary ? theme.accent.opacity(0.45) : theme.hairline
    }
}

extension Notification.Name {
    static let clipFlowFocusSearch = Notification.Name("clipFlow.focusSearch")
}
