import UIKit

/// Cancel and Done above the keyboard for every text box in the app. Done keeps what you typed.
/// Cancel puts back whatever was there when the keyboard came up.
@MainActor
final class KeyboardBar: NSObject {
    static let shared = KeyboardBar()

    private weak var field: UIView?
    private var original = ""

    private lazy var bar: UIToolbar = {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
        toolbar.items = [cancel, UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        toolbar.sizeToFit()
        return toolbar
    }()

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(began(_:)), name: UITextField.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(began(_:)), name: UITextView.textDidBeginEditingNotification, object: nil)
    }

    @objc private func began(_ note: Notification) {
        if let textField = note.object as? UITextField {
            field = textField
            original = textField.text ?? ""
            if textField.inputAccessoryView !== bar {
                textField.inputAccessoryView = bar
                textField.reloadInputViews()
            }
        } else if let textView = note.object as? UITextView, textView.isEditable {
            field = textView
            original = textView.text ?? ""
            if textView.inputAccessoryView !== bar {
                textView.inputAccessoryView = bar
                textView.reloadInputViews()
            }
        }
    }

    @objc private func doneTapped() {
        field?.resignFirstResponder()
    }

    /// Replaces the text the same way typing would, so the screen's own copy of it updates too.
    @objc private func cancelTapped() {
        if let input = field as? (UIView & UITextInput & UIKeyInput) {
            if let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument) {
                input.selectedTextRange = all
            }
            if original.isEmpty {
                if input.hasText { input.deleteBackward() }
            } else {
                input.insertText(original)
            }
        }
        field?.resignFirstResponder()
    }
}
