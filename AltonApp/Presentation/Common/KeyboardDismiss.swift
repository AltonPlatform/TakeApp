import SwiftUI
import UIKit

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }

    /// Adds a keyboard accessory "Done" button that resigns first responder.
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButtonModifier())
    }

    /// Adds a keyboard accessory "Done" button that clears a FocusState.
    func keyboardDoneButton(focus: FocusState<Bool>.Binding) -> some View {
        modifier(KeyboardDoneFocusModifier(focus: focus))
    }
}

private struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    KeyboardDismiss.dismiss()
                }
            )
    }
}

private struct KeyboardDoneButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    KeyboardDismiss.dismiss()
                }
            }
        }
    }
}

private struct KeyboardDoneFocusModifier: ViewModifier {
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focus.wrappedValue = false
                }
            }
        }
    }
}

enum KeyboardDismiss {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Shared UIToolbar for UITextView / UITextField inputAccessoryView.
    static func makeDoneAccessoryToolbar(
        target: Any?,
        action: Selector,
        width: CGFloat = UIScreen.main.bounds.width
    ) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: width, height: 44))
        toolbar.barStyle = .default
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: target, action: action)
        toolbar.items = [flex, done]
        toolbar.sizeToFit()
        return toolbar
    }
}
