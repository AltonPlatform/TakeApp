import XCTest
import SwiftUI
@testable import AltonApp

final class LiquidGlassDismissAdoptionTests: XCTestCase {
    /// Smoke test verifying that composer sheets accept .liquidGlassKeyboardDismiss(controller:)
    /// and that the controller's runtime state is initialized and reactive.
    ///
    /// Note on omitted views:
    /// - ReplyTakeView, CommentsView, TakePostDetailView, and ShotCommentsSheet require
    ///   heavyweight ViewModel dependencies (CommentsViewModel with CommentsUseCase &
    ///   PostActivityUseCase, PostEngagementController, etc.). They are verified via compile-time
    ///   conformance and call-site adoption rather than instantiating fake ViewModel hierarchies.
    @MainActor
    func testComposerSheetsAcceptLiquidGlassDismissModifier() {
        let controller = KeyboardDismissController()

        _ = LocationPickerSheet(selected: .constant(nil))
            .liquidGlassKeyboardDismiss(controller: controller)

        _ = HashtagInsertSheet(caption: .constant(""), query: .constant(""))
            .liquidGlassKeyboardDismiss(controller: controller)

        _ = CommentComposerFullScreenView(
            draft: .constant(""),
            attachments: .constant([]),
            isSubmitting: false,
            onCancel: {},
            onSubmit: {}
        ).liquidGlassKeyboardDismiss(controller: controller)

        _ = CommentGIFPickerSheet(onPicked: { _ in })
            .liquidGlassKeyboardDismiss(controller: controller)

        // Runtime assertions: controller begins in hidden state and responds to dismiss
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)

        // Verify notification updates state
        let frame = CGRect(x: 0, y: 500, width: 390, height: 340)
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: frame]
        )
        XCTAssertTrue(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 340)

        controller.dismiss()

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
    }

    /// Verifies that composer views adopt LiquidGlassKeyboardDismissButton in their body
    /// and no longer contain the legacy KeyboardDoneButtonModifier.
    @MainActor
    func testComposerViewsAdoptLiquidGlassDismissInBody() {
        let locationSheetBody = String(reflecting: LocationPickerSheet(selected: .constant(nil)).body)
        XCTAssertTrue(
            locationSheetBody.contains("LiquidGlassKeyboardDismissButton"),
            "LocationPickerSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            locationSheetBody.contains("KeyboardDoneButtonModifier"),
            "LocationPickerSheet body should not include KeyboardDoneButtonModifier"
        )

        let hashtagSheetBody = String(reflecting: HashtagInsertSheet(caption: .constant(""), query: .constant("")).body)
        XCTAssertTrue(
            hashtagSheetBody.contains("LiquidGlassKeyboardDismissButton"),
            "HashtagInsertSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            hashtagSheetBody.contains("KeyboardDoneButtonModifier"),
            "HashtagInsertSheet body should not include KeyboardDoneButtonModifier"
        )

        let gifPickerBody = String(reflecting: CommentGIFPickerSheet(onPicked: { _ in }).body)
        XCTAssertTrue(
            gifPickerBody.contains("LiquidGlassKeyboardDismissButton"),
            "CommentGIFPickerSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            gifPickerBody.contains("KeyboardDoneButtonModifier"),
            "CommentGIFPickerSheet body should not include KeyboardDoneButtonModifier"
        )

        let commentComposerBody = String(reflecting: CommentComposerFullScreenView(
            draft: .constant(""),
            attachments: .constant([]),
            isSubmitting: false,
            onCancel: {},
            onSubmit: {}
        ).body)
        XCTAssertTrue(
            commentComposerBody.contains("LiquidGlassKeyboardDismissButton"),
            "CommentComposerFullScreenView body should include LiquidGlassKeyboardDismissButton"
        )
    }
}
