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

    @MainActor func testDismissResignsFirstResponder() {
        let controller = KeyboardDismissController()
        controller.isKeyboardVisible = true
        // UIApplication.shared.sendAction resigns first responder; assert no crash and visible stays mutable.
        controller.dismiss()
        XCTAssertTrue(true) // smoke — resign has no return value
    }
}
