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

/// Status shown with a symbol and text, never color alone.
struct StatusLabel: View {
    let status: SlotStatus
    var compact = false

    var body: some View {
        switch status {
        case .taken(let e):
            Label(compact ? Format.time12(e.takenAt) : "Taken \(Format.time12(e.takenAt))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.taken)
        case .due:
            Label("Due Now", systemImage: "clock.fill").foregroundStyle(Palette.due)
        case .later:
            Label("Later", systemImage: "clock").foregroundStyle(Palette.secondary)
        case .missed:
            Label("Not Logged", systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.missed)
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
