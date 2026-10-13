import SwiftUI
import UIKit

/// Apple's semantic colors. They adapt to Dark Mode, Increase Contrast and elevated (sheet) backgrounds on their own.
enum Palette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)
    static let label = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)
    static let accent = Color.orange
    static let taken = Color.green
    static let due = Color.orange
    static let missed = Color.red
}

extension LidColor {
    var color: Color {
        switch self {
        case .amber: return .orange
        case .red: return .red
        case .pink: return .pink
        case .plum: return .purple
        case .indigo: return .indigo
        case .blue: return .blue
        case .cyan: return .cyan
        case .teal: return .teal
        case .mint: return .mint
        case .green: return .green
        case .yellow: return .yellow
        case .slate: return .gray
        }
    }
}

/// The jar's icon: its form's SF Symbol on a tinted circle, like the Health app's medication icons.
struct JarIcon: View {
    let jar: Jar
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(jar.lid.color.gradient.opacity(0.22))
            Image(systemName: jar.form.symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(jar.lid.color.gradient)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension InteractionLevel {
    var color: Color {
        switch self {
        case .major: return .red
        case .moderate: return .orange
        case .minor: return .yellow
        }
    }
}

/// Status shown with a symbol and text, never color alone.
struct StatusLabel: View {
    let status: SlotStatus
    var compact = false

    var body: some View {
        switch status {
        case .taken(let e):
            Label(compact ? Format.time12(e.takenAt) : "Taken \(Format.time12(e.takenAt))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.taken)
        case .skipped:
            Label("Skipped", systemImage: "forward.end.circle").foregroundStyle(Palette.secondary)
        case .due:
            Label("Due Now", systemImage: "clock.fill").foregroundStyle(Palette.due)
        case .later:
            Label("Later", systemImage: "clock").foregroundStyle(Palette.secondary)
        case .missed:
            Label("Missed", systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed)
        case .asNeeded:
            Label("As Needed", systemImage: "circle.dashed").foregroundStyle(Palette.secondary)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26, a standard material before that. Only for floating controls, never content.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Prominent tinted glass button on iOS 26, bordered prominent before that.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Accent color

/// The app's accent: a system preset (with its own light and dark shades) or a custom hex color.
enum AccentChoice {
    struct Preset: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    static let defaultId = "orange"

    static let presets: [Preset] = [
        Preset(id: "orange", name: "Orange", color: .orange),
        Preset(id: "red", name: "Red", color: .red),
        Preset(id: "pink", name: "Pink", color: .pink),
        Preset(id: "purple", name: "Purple", color: .purple),
        Preset(id: "indigo", name: "Indigo", color: .indigo),
        Preset(id: "blue", name: "Blue", color: .blue),
        Preset(id: "cyan", name: "Cyan", color: .cyan),
        Preset(id: "teal", name: "Teal", color: .teal),
        Preset(id: "mint", name: "Mint", color: .mint),
        Preset(id: "green", name: "Green", color: .green),
        Preset(id: "yellow", name: "Yellow", color: .yellow),
        Preset(id: "brown", name: "Brown", color: .brown),
        Preset(id: "graphite", name: "Graphite", color: Color(uiColor: .systemGray)),
    ]

    static func color(for value: String?) -> Color {
        let v = (value ?? defaultId).trimmingCharacters(in: .whitespaces)
        if let p = presets.first(where: { $0.id == v.lowercased() }) { return p.color }
        if let ui = UIColor(hex: v) { return Color(uiColor: readable(ui)) }
        return .orange
    }

    static func name(for value: String?) -> String {
        let v = (value ?? defaultId).lowercased()
        if let p = presets.first(where: { $0.id == v }) { return p.name }
        if let hex = normalizedHex(value) { return hex }
        return "Orange"
    }

    /// "#RRGGBB" from user input like "ff9500", "#F90" or "#ff9500"; nil if it isn't a color.
    static func normalizedHex(_ input: String?) -> String? {
        guard let input else { return nil }
        var h = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, h.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + h
    }

    /// Custom colors get a light and a dark shade, nudged only as far as needed to stay readable
    /// on Apple's black (dark) and white (light) backgrounds.
    static func readable(_ base: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? base.adjusted(minLuminance: 0.16) : base.adjusted(maxLuminance: 0.62)
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        guard let n = AccentChoice.normalizedHex(hex), let v = UInt32(n.dropFirst(), radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !getRed(&r, green: &g, blue: &b, alpha: &a) {
            let c = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
            let comps = c?.components ?? [0, 0, 0]
            r = comps.count > 0 ? comps[0] : 0; g = comps.count > 1 ? comps[1] : r; b = comps.count > 2 ? comps[2] : r
        }
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    var hexString: String {
        let c = rgb
        return String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    var luminance: CGFloat {
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let c = rgb
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        let a = rgb, b = other.rgb
        return UIColor(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, alpha: 1)
    }

    func adjusted(minLuminance: CGFloat) -> UIColor {
        var c = self, step: CGFloat = 0
        while c.luminance < minLuminance && step < 1 { step += 0.05; c = mixed(with: .white, step) }
        return c
    }

    func adjusted(maxLuminance: CGFloat) -> UIColor {
        var c = self, step: CGFloat = 0
        while c.luminance > maxLuminance && step < 1 { step += 0.05; c = mixed(with: .black, step) }
        return c
    }
}

/// A jar's two names: the medication or supplement in full white, the jar's label smaller and lighter beneath it.
struct JarNameStack: View {
    let name: String
    let label: String
    var large = false

    init(jar: Jar, large: Bool = false) {
        self.name = jar.name
        self.label = jar.labelName
        self.large = large
    }

    init(name: String, label: String, large: Bool = false) {
        self.name = name
        self.label = label
        self.large = large
    }

    var body: some View {
        VStack(alignment: large ? .center : .leading, spacing: large ? 3 : 1) {
            Text(name)
                .font(large ? .title.weight(.bold) : .headline)
                .foregroundStyle(Palette.label)
            if !label.isEmpty {
                Text(label)
                    .font(large ? .body : .subheadline)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .multilineTextAlignment(large ? .center : .leading)
    }
}
