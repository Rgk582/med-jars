import SwiftUI

struct SectionTitle: View {
    let text: String
    var color: Color = Palette.muted
    var body: some View {
        Text(text.uppercased())
            .font(Typo.display(15, .semibold))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

struct StatusChip: View {
    let status: SlotStatus
    var body: some View {
        let (text, fg, bg, outlined): (String, Color, Color, Bool) = {
            switch status {
            case .taken(let e): return ("Taken \(Format.time12(e.takenAt))", Palette.ok, Palette.okSoft, false)
            case .due: return ("Due now", Palette.onAmber, Palette.amber, false)
            case .later: return ("Later", Palette.muted, .clear, true)
            case .missed: return ("Not logged", Palette.alert, Palette.alertSoft, false)
            case .asNeeded: return ("As needed", Palette.muted, .clear, true)
            }
        }()
        Text(text.uppercased())
            .font(Typo.display(13, .semibold))
            .tracking(0.6)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay { if outlined { Capsule().strokeBorder(Palette.line) } }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line))
    }
}

/// Dashed rule like the perforations between lines on a pharmacy label.
struct DashedRule: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                GeometryReader { geo in
                    Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            )
    }
}

struct WarningSticker: View {
    let text: String
    let alternate: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(alternate ? Palette.sticker2 : Palette.sticker)
                .frame(width: 18, height: 18)
                .background(Palette.stickerInk, in: Circle())
            Text(text.uppercased())
                .font(Typo.display(15, .semibold))
                .tracking(0.3)
                .foregroundStyle(Palette.stickerInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(alternate ? Palette.sticker2 : Palette.sticker, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct EmptyCard: View {
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Typo.display(22)).foregroundStyle(Palette.ink)
            Text(message).foregroundStyle(Palette.muted)
            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle).font(.headline)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Palette.amber, in: Capsule())
                        .foregroundStyle(Palette.onAmber)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// What the editor sheet is editing: an existing jar, or a new one (optionally with a preset tag id).
struct EditorTarget: Identifiable {
    let id = UUID()
    let jar: Jar?
    var presetId: String = ""
}
