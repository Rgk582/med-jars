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

extension DoseSlot {
    func amountLine(_ form: PillForm) -> String {
        [amount, Format.pills(pills, form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

extension DoseEntry {
    var amountLine: String {
        [amount, Format.pills(pills, form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ").ifEmpty("Dose")
    }
}
