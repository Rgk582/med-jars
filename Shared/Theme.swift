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
        case .white: return Color(red: 0.97, green: 0.97, blue: 0.96)
        case .cream: return Color(red: 0.96, green: 0.92, blue: 0.80)
        case .peach: return Color(red: 1.0, green: 0.78, blue: 0.62)
        case .brown: return .brown
        case .lightBlue: return Color(red: 0.62, green: 0.80, blue: 1.0)
        case .lavender: return Color(red: 0.78, green: 0.72, blue: 1.0)
        }
    }
}

/// The jar's icon: a drawing of the pill itself on black, in its color and shape, so it's easy to tell jars apart.
struct JarIcon: View {
    let jar: Jar
    /// A specific jar of the substance; the default jar when nil.
    var bottle: Bottle? = nil
    var size: CGFloat = 40

    var body: some View {
        BottleIcon(bottle: bottle ?? jar.defaultBottle, size: size)
    }
}

/// One jar's pill drawing.
struct BottleIcon: View {
    let bottle: Bottle
    var size: CGFloat = 40

    var body: some View {
        PillArt(form: bottle.form, shape: bottle.pillShape, color: bottle.lid.color, scoreLine: bottle.scoreLine,
                imprint: bottle.imprint, placement: bottle.imprintPlacement, size: size)
    }
}

/// A drawing of one dose with no background: the form's shape (tablet, capsule, softgel, gummy, scoop,
/// powder, drop, smoked, other) in the chosen color, with a tablet's shape, score line and imprint.
struct PillArt: View {
    let form: PillForm
    var shape: PillShape = .round
    let color: Color
    var scoreLine = false
    var imprint = ""
    var placement: ImprintPlacement = .left
    let size: CGFloat

    private var line: CGFloat { max(0.6, size * 0.014) }
    private var edge: Color { color.mix(with: .black, by: 0.28) }
    private var ink: Color { color.mix(with: .black, by: 0.5) }
    private var body3D: LinearGradient {
        LinearGradient(colors: [color.mix(with: .white, by: 0.35), color, color.mix(with: .black, by: 0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var showImprint: Bool { size >= 44 && form.hasImprint && !imprint.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // With no tile behind it, the pill fills most of its space.
        art
            .scaleEffect(1.38)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The imprint cut in two, at a space when there is one: "DP 30" becomes "DP" and "30".
    private var halves: (String, String) {
        let t = imprint.trimmingCharacters(in: .whitespaces)
        if let space = t.firstIndex(of: " ") {
            return (String(t[..<space]).trimmingCharacters(in: .whitespaces), String(t[space...]).trimmingCharacters(in: .whitespaces))
        }
        let mid = t.index(t.startIndex, offsetBy: t.count / 2)
        return (String(t[..<mid]), String(t[mid...]))
    }

    /// The imprint on a pill split into two halves `offset` apart, or on one half.
    @ViewBuilder private func sidedImprint(width: CGFloat, offset: CGFloat) -> some View {
        switch placement {
        case .split:
            let (a, b) = halves
            imprintText(a, width).offset(x: -offset)
            imprintText(b, width).offset(x: offset)
        case .left:
            imprintText(imprint, width).offset(x: -offset)
        case .right:
            imprintText(imprint, width).offset(x: offset)
        }
    }

    @ViewBuilder private var art: some View {
        switch form {
        case .tablet: tablet
        case .capsule: capsule
        case .softgel: softgel
        case .gummy: gummy
        case .scoop: scoop
        case .powderG, .powderMg: powder
        case .drop: drop
        case .smoked: smoked
        case .other: other
        }
    }

    private func imprintText(_ maxWidth: CGFloat) -> some View {
        imprintText(imprint, maxWidth)
    }

    private func imprintText(_ text: String, _ maxWidth: CGFloat) -> some View {
        Text(text.trimmingCharacters(in: .whitespaces))
            .font(.system(size: size * 0.1, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: maxWidth)
    }

    private var tablet: some View {
        let dims: (CGFloat, CGFloat)
        let outline: AnyShape
        switch shape {
        case .round: dims = (0.62, 0.62); outline = AnyShape(Circle())
        case .oval: dims = (0.72, 0.48); outline = AnyShape(Ellipse())
        case .oblong: dims = (0.76, 0.36); outline = AnyShape(Capsule())
        }
        let w = dims.0 * size, h = dims.1 * size
        return ZStack {
            outline.fill(body3D)
            outline.stroke(edge, lineWidth: line)
            // Bevel: a lighter rim inside the edge.
            outline.scale(0.84).stroke(Color.white.opacity(0.18), lineWidth: line)
            if scoreLine {
                Capsule().fill(ink.opacity(0.75)).frame(width: max(1, size * 0.022), height: h * 0.86)
            }
            if showImprint {
                if scoreLine {
                    sidedImprint(width: w * 0.36, offset: w * 0.22)
                } else {
                    imprintText(w * 0.7)
                }
            }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(shape == .round ? 0 : -20))
    }

    private var capsule: some View {
        let w = 0.76 * size, h = 0.32 * size
        return ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(color)
                Rectangle().fill(color.mix(with: .white, by: 0.22))
            }
            .clipShape(Capsule())
            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.4), .clear, Color.black.opacity(0.22)],
                                          startPoint: .top, endPoint: .bottom))
            Rectangle().fill(Color.black.opacity(0.22)).frame(width: max(1, size * 0.016), height: h)
            Capsule().stroke(edge, lineWidth: line)
            if showImprint { sidedImprint(width: w * 0.34, offset: w * 0.22) }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(-35))
    }

    private var softgel: some View {
        let w = 0.70 * size, h = 0.46 * size
        return ZStack {
            Ellipse().fill(color.opacity(0.88))
            Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.65), .clear], center: UnitPoint(x: 0.32, y: 0.3),
                                          startRadius: 0, endRadius: size * 0.22))
            Ellipse().fill(LinearGradient(colors: [.clear, Color.black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
            Ellipse().stroke(edge.opacity(0.8), lineWidth: line)
            if showImprint { imprintText(w * 0.6) }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(-25))
    }

    private var gummy: some View {
        let u = size
        return ZStack {
            Group {
                Circle().frame(width: u * 0.13).offset(x: -u * 0.11, y: -u * 0.27)
                Circle().frame(width: u * 0.13).offset(x: u * 0.11, y: -u * 0.27)
                Circle().frame(width: u * 0.27).offset(y: -u * 0.17)
                Ellipse().frame(width: u * 0.36, height: u * 0.38).offset(y: u * 0.08)
                Circle().frame(width: u * 0.13).offset(x: -u * 0.19, y: u * 0.0)
                Circle().frame(width: u * 0.13).offset(x: u * 0.19, y: u * 0.0)
                Circle().frame(width: u * 0.15).offset(x: -u * 0.12, y: u * 0.25)
                Circle().frame(width: u * 0.15).offset(x: u * 0.12, y: u * 0.25)
            }
            .foregroundStyle(color.opacity(0.9))
            Ellipse().fill(Color.white.opacity(0.35)).frame(width: u * 0.08, height: u * 0.05).offset(x: -u * 0.05, y: -u * 0.22)
            Ellipse().fill(Color.white.opacity(0.25)).frame(width: u * 0.1, height: u * 0.16).offset(x: -u * 0.08, y: u * 0.06)
        }
        .compositingGroup()
    }

    private var scoop: some View {
        let u = size
        return ZStack {
            Capsule().fill(Color(white: 0.75)).frame(width: u * 0.34, height: u * 0.07).offset(x: u * 0.2, y: u * 0.06)
            UnevenRoundedRectangle(topLeadingRadius: u * 0.02, bottomLeadingRadius: u * 0.1,
                                   bottomTrailingRadius: u * 0.1, topTrailingRadius: u * 0.02)
                .fill(Color(white: 0.85))
                .frame(width: u * 0.36, height: u * 0.24)
                .offset(x: -u * 0.08, y: u * 0.1)
            Ellipse().fill(body3D).frame(width: u * 0.38, height: u * 0.2).offset(x: -u * 0.08, y: -u * 0.03)
        }
    }

    private var powder: some View {
        let u = size
        return ZStack {
            MoundShape().fill(body3D).frame(width: u * 0.7, height: u * 0.36).offset(y: u * 0.1)
            ForEach(0..<7, id: \.self) { i in
                let xs: [CGFloat] = [-0.3, -0.22, 0.26, 0.31, -0.12, 0.16, 0.0]
                let ys: [CGFloat] = [0.27, 0.22, 0.26, 0.21, -0.02, -0.03, -0.12]
                Circle().fill(color.opacity(0.85)).frame(width: u * 0.03).offset(x: u * xs[i], y: u * ys[i])
            }
        }
    }

    private var drop: some View {
        let u = size
        return ZStack {
            DropShape().fill(body3D)
            DropShape().stroke(edge, lineWidth: line)
            Ellipse().fill(Color.white.opacity(0.45)).frame(width: u * 0.07, height: u * 0.12).offset(x: -u * 0.07, y: u * 0.04)
        }
        .frame(width: u * 0.42, height: u * 0.6)
    }

    private var smoked: some View {
        let u = size
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: u * 0.66, y: u * 0.32))
                p.addCurve(to: CGPoint(x: u * 0.74, y: u * 0.1), control1: CGPoint(x: u * 0.58, y: u * 0.22), control2: CGPoint(x: u * 0.82, y: u * 0.2))
            }
            .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: max(1, u * 0.025), lineCap: .round))
            .frame(width: u, height: u)
            HStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.85, green: 0.7, blue: 0.5)).frame(width: u * 0.14)
                Rectangle().fill(color)
                Rectangle().fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)).frame(width: u * 0.06)
            }
            .frame(width: u * 0.66, height: u * 0.13)
            .clipShape(RoundedRectangle(cornerRadius: u * 0.03))
            .rotationEffect(.degrees(-30))
            .offset(x: -u * 0.03, y: u * 0.08)
        }
    }

    private var other: some View {
        let w = 0.6 * size, h = 0.4 * size
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).fill(body3D)
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).stroke(edge, lineWidth: line)
            if showImprint { imprintText(w * 0.75) }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(-15))
    }
}

/// A heap of powder.
struct MoundShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY),
                   control2: CGPoint(x: r.midX - r.width * 0.22, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY), control1: CGPoint(x: r.midX + r.width * 0.22, y: r.minY),
                   control2: CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A liquid drop, point up.
struct DropShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = r.width / 2
        let center = CGPoint(x: r.midX, y: r.maxY - radius)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: center.y), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
        p.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
        p.closeSubpath()
        return p
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
        case .waiting:
            Label("Waiting", systemImage: "hourglass").foregroundStyle(Palette.secondary)
        case .reminder:
            Label("Not Logged", systemImage: "bell").foregroundStyle(Palette.secondary)
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
