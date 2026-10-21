import SwiftUI
import UIKit

/// Cancel and Done above the keyboard for every text box in the app. Done keeps what you typed.
/// Cancel puts back whatever was there when the keyboard came up.
///
/// The bar itself is SwiftUI's keyboard toolbar (`keyboardBar()` on each screen with text boxes). Setting a UIKit
/// accessory view on the text box didn't stick: SwiftUI puts its own back as soon as the screen updates, so the bar
/// vanished after the first keystroke. This class only remembers which box is being edited and what it held.
@MainActor
final class KeyboardBar: NSObject {
    static let shared = KeyboardBar()

    private weak var field: UIView?
    private var original = ""

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(began(_:)), name: UITextField.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(began(_:)), name: UITextView.textDidBeginEditingNotification, object: nil)
    }

    @objc private func began(_ note: Notification) {
        if let textField = note.object as? UITextField {
            field = textField
            original = textField.text ?? ""
        } else if let textView = note.object as? UITextView, textView.isEditable {
            field = textView
            original = textView.text ?? ""
        }
    }

    func done() {
        if let field, field.isFirstResponder {
            field.resignFirstResponder()
        } else {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// Replaces the text the same way typing would, so the screen's own copy of it updates too.
    func cancel() {
        if let input = field as? (UIView & UITextInput & UIKeyInput), input.isFirstResponder {
            if let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument) {
                input.selectedTextRange = all
            }
            if original.isEmpty {
                if input.hasText { input.deleteBackward() }
            } else {
                input.insertText(original)
            }
        }
        done()
    }
}

extension View {
    /// Cancel and Done above the keyboard for the text boxes on this screen. Put it once on each screen that has
    /// text boxes (a sheet, or a page pushed inside one), next to the screen's other toolbar items.
    func keyboardBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Cancel") { KeyboardBar.shared.cancel() }
                    .accessibilityIdentifier("keyboard-cancel")
                Spacer()
                Button("Done") { KeyboardBar.shared.done() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("keyboard-done")
            }
        }
    }
}
