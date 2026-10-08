import XCTest
@testable import AltonApp

final class KeyboardDismissControllerTests: XCTestCase {
    @MainActor func testVisibleTogglesWithKeyboardNotifications() {
        let controller = KeyboardDismissController()
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
        let frame = CGRect(x: 0, y: 600, width: 390, height: 296)
        let userInfo: [AnyHashable: Any] = [UIResponder.keyboardFrameEndUserInfoKey: frame]
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: userInfo)
        XCTAssertTrue(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 296)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
    }

    @MainActor func testVisibleWithNilUserInfoResetsKeyboardHeightToZero() {
        let controller = KeyboardDismissController()
        controller.keyboardHeight = 250 // Pre-existing height to verify reset
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: nil)
        XCTAssertTrue(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
    }

    @MainActor func testDismissResignsFirstResponder() {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let textField = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        defer {
            textField.removeFromSuperview()
            window.resignKey()
            window.isHidden = true
        }

        let becameFirstResponder = textField.becomeFirstResponder()
        XCTAssertTrue(becameFirstResponder)
        XCTAssertTrue(textField.isFirstResponder)

        let controller = KeyboardDismissController()
        controller.isKeyboardVisible = true
        controller.dismiss()

        XCTAssertFalse(textField.isFirstResponder, "Dismiss should resign first responder")
    }
}
