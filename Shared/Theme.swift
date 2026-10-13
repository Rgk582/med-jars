import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// A color that switches between a light and a dark value with the system appearance.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Pharmacy-label palette: clinical grey ground, white label stock, amber bottle accent,
/// yellow and orange auxiliary warning stickers.
enum Palette {
    static let bg = Color.dynamic(0xECEFED, 0x111412)
    static let paper = Color.dynamic(0xFFFFFF, 0x1B1F1D)
    static let ink = Color.dynamic(0x1A1D1B, 0xE7ECE9)
    static let muted = Color.dynamic(0x59625D, 0x9BA49F)
    static let line = Color.dynamic(0xD2D8D4, 0x2F3532)
    static let amber = Color.dynamic(0xA9560A, 0xEC9A3E)
    static let onAmber = Color.dynamic(0xFFFFFF, 0x1B1206)
    static let amberSoft = Color.dynamic(0xF7E7D2, 0x33261A)
    static let amberInk = Color.dynamic(0x57300A, 0xF5D3A8)
    static let sticker = Color.dynamic(0xFFD84A, 0xE9C53C)
    static let sticker2 = Color.dynamic(0xFFB13D, 0xE79E36)
    static let stickerInk = Color.dynamic(0x2A2200, 0x221B00)
    static let ok = Color.dynamic(0x1F7546, 0x63C38C)
    static let okSoft = Color.dynamic(0xDCEFE3, 0x173126)
    static let alert = Color.dynamic(0xAE2A20, 0xF2877D)
    static let alertSoft = Color.dynamic(0xFBE2DF, 0x3A1E1B)
    static let onLid = Color.dynamic(0xFFFFFF, 0x121412)
}

extension LidColor {
    var color: Color {
        switch self {
        case .amber: return .dynamic(0xC0670F, 0xE8913A)
        case .teal: return .dynamic(0x15807A, 0x42B8AF)
        case .plum: return .dynamic(0x8C3A7A, 0xCB7DB9)
        case .blue: return .dynamic(0x2C5CAE, 0x79A0EA)
        case .green: return .dynamic(0x4A8427, 0x8BC463)
        case .red: return .dynamic(0xBC3A29, 0xEE7765)
        case .slate: return .dynamic(0x55616C, 0x9AA7B3)
        }
    }
    var name: String { rawValue.capitalized }
}

enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A spice-jar lid seen from above: solid cap, knurled rim, initials.
struct LidView: View {
    let lid: LidColor
    let text: String
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(lid.color)
            Circle()
                .strokeBorder(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: size * 0.09, dash: [size * 0.045, size * 0.045]))
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .padding(size * 0.1)
            if !text.isEmpty {
                Text(text)
                    .font(Typo.display(size * 0.36))
                    .foregroundStyle(Palette.onLid)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
