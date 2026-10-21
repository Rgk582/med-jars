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
    var deleted = false
    let onUndo: () -> Void

    /// How long a toast stays up, in nanoseconds. UI tests launch with -longToasts: reading the screen for a test
    /// stalls the app for seconds at a time, so a toast could come and go before the test sees it.
    static var lifetime: UInt64 {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-longToasts") { return 20_000_000_000 }
        #endif
        return 6_000_000_000
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deleted ? "trash.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(deleted ? Palette.missed : Palette.taken)
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
    /// Editing a logged dose: 0 deletes it.
    var allowZero = false

    static func step(_ n: Double, up: Bool, form: PillForm, allowZero: Bool = false) -> Double {
        let unit = form.step
        let units = n / unit
        let next = up ? (units + 0.0001).rounded(.down) + 1 : (units - 0.0001).rounded(.up) - 1
        return min(50, max(allowZero ? 0 : unit, next * unit))
    }

    private func change(up: Bool) {
        withAnimation(.snappy) { count = Self.step(count, up: up, form: form, allowZero: allowZero) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    var body: some View {
        HStack {
            Button { change(up: false) } label: {
                Image(systemName: "minus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(count <= (allowZero ? 0 : form.step))
            Spacer()
            VStack(spacing: 0) {
                Text(Format.count(count))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: count))
                Text(count > 0 && count <= 1 ? form.singular : form.plural)
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

/// The big amount control in the log and plan sheets: the pill counter, or a typed amount for powders in g or mg.
struct AmountInput: View {
    @Binding var amount: Double
    let form: PillForm
    var allowZero = false
    @State private var text = ""

    var body: some View {
        if form.isMeasured {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(form.singular).font(.title2.weight(.semibold)).foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 4)
            .onAppear { text = Format.trimmed(amount) }
            .onChange(of: text) { _, new in
                if let v = Double(new.replacingOccurrences(of: ",", with: ".")), v > 0 || (allowZero && v == 0) { amount = v }
            }
            .onChange(of: amount) { _, new in
                if Double(text.replacingOccurrences(of: ",", with: ".")) != new { text = Format.trimmed(new) }
            }
        } else {
            PillCounter(count: $amount, form: form, allowZero: allowZero)
        }
    }
}

/// A form row for an amount: a stepper in the form's steps, or a typed amount for powders in g or mg.
struct AmountField: View {
    let title: String
    @Binding var amount: Double
    let form: PillForm
    @State private var text = ""

    var body: some View {
        if form.isMeasured {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(form.singular).foregroundStyle(Palette.secondary)
                }
            }
            .onAppear { text = Format.trimmed(amount) }
            .onChange(of: text) { _, new in
                if let v = Double(new.replacingOccurrences(of: ",", with: ".")), v > 0 { amount = v }
            }
            .onChange(of: amount) { _, new in
                if Double(text.replacingOccurrences(of: ",", with: ".")) != new { text = Format.trimmed(new) }
            }
        } else {
            Stepper(value: $amount, in: form.step...100, step: form.step) {
                LabeledContent(title, value: Format.pills(amount, form))
            }
        }
    }
}
