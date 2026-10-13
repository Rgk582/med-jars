import SwiftUI
import UIKit

/// What the editor sheet is editing: an existing jar, or a new one (optionally with a preset link name or a tag to pair).
struct EditorTarget: Identifiable {
    let id = UUID()
    let jar: Jar?
    var presetId: String = ""
    var pairTagUID: String = ""
}

/// A tag the app doesn't recognize yet, waiting to be paired.
struct UnknownTag: Identifiable {
    let id = UUID()
    let tag: ScannedTag
}

/// A floating "Logged … Undo" confirmation on Liquid Glass.
struct UndoToast: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.taken)
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .secondaryButton()
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .glassPanel(cornerRadius: 24)
        .padding(.horizontal, 16)
    }
}

/// Haptic used whenever a dose gets logged.
enum Haptics {
    static func logged() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Shared scan-then-route behavior for the Scan Jar button and the unknown-tag sheet.
struct ScanAlert: Identifiable {
    let id = UUID()
    let message: String
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}


extension DoseEntry {
    var amountLine: String {
        [amount, Format.pills(pills, form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ").ifEmpty("Dose")
    }
}

/// Big minus / count / plus control for how many pills a dose is. Halvable forms step in halves,
/// capsules, softgels, drops and hits in whole numbers.
struct PillCounter: View {
    @Binding var count: Double
    let form: PillForm

    static func step(_ n: Double, up: Bool, form: PillForm) -> Double {
        let unit = form.step
        let units = n / unit
        let next = up ? (units + 0.0001).rounded(.down) + 1 : (units - 0.0001).rounded(.up) - 1
        return min(50, max(unit, next * unit))
    }

    private func change(up: Bool) {
        withAnimation(.snappy) { count = Self.step(count, up: up, form: form) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    var body: some View {
        HStack {
            Button { change(up: false) } label: {
                Image(systemName: "minus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(count <= form.step)
            Spacer()
            VStack(spacing: 0) {
                Text(Format.count(count))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: count))
                Text(count <= 1 ? form.singular : form.plural)
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button { change(up: true) } label: {
                Image(systemName: "plus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(count >= 50)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount")
        .accessibilityValue(Format.pills(count, form))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(up: true)
            case .decrement: change(up: false)
            @unknown default: break
            }
        }
    }
}
