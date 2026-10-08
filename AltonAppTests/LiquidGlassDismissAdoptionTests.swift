import XCTest
import SwiftUI
@testable import AltonApp

final class LiquidGlassDismissAdoptionTests: XCTestCase {
    /// Compile-time check asserting that composer sheets accept .liquidGlassKeyboardDismiss(controller:)
    /// and .liquidGlassKeyboardDismiss(controller:bottomInset:).
    ///
    /// The successful compilation of these view modifier invocations serves as the assertion.
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

        // Verifies that liquidGlassKeyboardDismiss accepts bottomInset parameter
        _ = EmptyView()
            .liquidGlassKeyboardDismiss(controller: controller, bottomInset: 64)
    }

    /// Verifies that composer views adopt LiquidGlassKeyboardDismissButton in their body
    /// and no longer contain legacy KeyboardDone modifiers (matching on "KeyboardDone" prefix
    /// to cover both KeyboardDoneButtonModifier and KeyboardDoneFocusModifier).
    @MainActor
    func testComposerViewsAdoptLiquidGlassDismissInBody() {
        let locationSheetBody = String(reflecting: LocationPickerSheet(selected: .constant(nil)).body)
        XCTAssertTrue(
            locationSheetBody.contains("LiquidGlassKeyboardDismissButton"),
            "LocationPickerSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            locationSheetBody.contains("KeyboardDone"),
            "LocationPickerSheet body should not include KeyboardDone modifier"
        )

        let hashtagSheetBody = String(reflecting: HashtagInsertSheet(caption: .constant(""), query: .constant("")).body)
        XCTAssertTrue(
            hashtagSheetBody.contains("LiquidGlassKeyboardDismissButton"),
            "HashtagInsertSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            hashtagSheetBody.contains("KeyboardDone"),
            "HashtagInsertSheet body should not include KeyboardDone modifier"
        )

        let gifPickerBody = String(reflecting: CommentGIFPickerSheet(onPicked: { _ in }).body)
        XCTAssertTrue(
            gifPickerBody.contains("LiquidGlassKeyboardDismissButton"),
            "CommentGIFPickerSheet body should include LiquidGlassKeyboardDismissButton"
        )
        XCTAssertFalse(
            gifPickerBody.contains("KeyboardDone"),
            "CommentGIFPickerSheet body should not include KeyboardDone modifier"
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
        XCTAssertFalse(
            commentComposerBody.contains("KeyboardDone"),
            "CommentComposerFullScreenView body should not include KeyboardDone modifier"
        )
    }
}
