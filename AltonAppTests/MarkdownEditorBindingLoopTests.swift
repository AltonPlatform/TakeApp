import UIKit
import XCTest
@testable import AltonApp

final class MarkdownEditorBindingLoopTests: XCTestCase {
    // MARK: - Helpers

    @MainActor
    private func makeEditor(
        markdown: String
    ) -> (coordinator: RichTextEditorView.Coordinator, textView: RichTextTextView) {
        let coordinator = RichTextEditorView.Coordinator(
            content: .constant(NSAttributedString()),
            pasteCodeHint: .constant(nil),
            onMarkdownChange: { _ in },
            onFormatStateChange: { _ in },
            onSelectionLengthChange: { _ in },
            onPlainCaretChange: { _, _ in },
            onHeightChange: { _ in }
        )
        let textView = RichTextTextView()
        textView.delegate = coordinator
        let initial = RichTextMarkdownConverter.attributedString(from: markdown)
        textView.attributedText = initial
        coordinator.textView = textView
        coordinator.lastExportedMarkdown = RichTextMarkdownConverter.markdown(from: initial)
        return (coordinator, textView)
    }

    /// Lets every `DispatchQueue.main.async` already queued run.
    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - pendingEdit

    @MainActor
    func testPendingEditConsumedSynchronously() {
        let (coordinator, textView) = makeEditor(markdown: "hello")
        textView.selectedRange = NSRange(location: 5, length: 0)

        coordinator.stagePendingEdit(PendingComposerEdit(id: 1, insert: " world"))
        let applied = coordinator.applyPendingEditIfNeeded(to: textView)

        XCTAssertTrue(applied)
        XCTAssertEqual(textView.attributedText.string, "hello world")
        XCTAssertNil(coordinator.pendingEdit, "pendingEdit must be cleared synchronously")
    }

    @MainActor
    func testSameEditIDIsAppliedOnlyOnce() {
        let (coordinator, textView) = makeEditor(markdown: "hi")
        textView.selectedRange = NSRange(location: 2, length: 0)
        let edit = PendingComposerEdit(id: 7, insert: "!")

        coordinator.stagePendingEdit(edit)
        coordinator.applyPendingEditIfNeeded(to: textView)
        // A re-entrant updateUIView sees the same (not yet cleared) binding value again.
        coordinator.stagePendingEdit(edit)
        let appliedAgain = coordinator.applyPendingEditIfNeeded(to: textView)

        XCTAssertFalse(appliedAgain)
        XCTAssertEqual(textView.attributedText.string, "hi!", "the same edit must never double-apply")
    }

    // MARK: - pendingFormatAction

    @MainActor
    func testPendingFormatActionConsumedSynchronouslyAndAppliedOnce() {
        let (coordinator, textView) = makeEditor(markdown: "hello")
        textView.selectedRange = NSRange(location: 0, length: 5)

        coordinator.stagePendingFormatAction(PendingFormatAction(id: 1, action: .bold))
        let applied = coordinator.applyPendingFormatActionIfNeeded(to: textView)
        XCTAssertTrue(applied)
        XCTAssertNil(coordinator.pendingFormatAction, "local mirror must be cleared once consumed")
        XCTAssertTrue(isBold(textView, at: 0))

        // Nothing staged any more: a second pass must not toggle bold off again.
        let appliedAgain = coordinator.applyPendingFormatActionIfNeeded(to: textView)
        XCTAssertFalse(appliedAgain)
        XCTAssertTrue(isBold(textView, at: 0), "format action must toggle exactly once")
    }

    /// Behavioral proof of the `**` duplication fix. The binding clear is deferred, so a
    /// re-entrant updateUIView pass (N+1) still sees the SAME action and re-stages it. Only the
    /// id guard stops it being applied twice. On the pre-fix code (no `consumedFormatActionID`)
    /// the second apply toggles bold back off, so the final assertions fail.
    @MainActor
    func testPendingFormatActionConsumedOnceByIdGuard() {
        let (coordinator, textView) = makeEditor(markdown: "hello")
        textView.selectedRange = NSRange(location: 0, length: 5)
        let action = PendingFormatAction(id: 1, action: .bold)

        // Pass N: stage + apply.
        coordinator.stagePendingFormatAction(action)
        XCTAssertTrue(coordinator.applyPendingFormatActionIfNeeded(to: textView))
        XCTAssertEqual(coordinator.consumedFormatActionID, 1)
        XCTAssertTrue(isBold(textView, at: 0))
        let markdownAfterFirst = RichTextMarkdownConverter.markdown(from: textView.attributedText)
        XCTAssertEqual(markdownAfterFirst, "**hello**")

        // Pass N+1 before the async binding clear ran: same id re-staged.
        coordinator.stagePendingFormatAction(action)
        let appliedAgain = coordinator.applyPendingFormatActionIfNeeded(to: textView)

        XCTAssertFalse(appliedAgain, "same id must be a no-op")
        XCTAssertTrue(isBold(textView, at: 0), "bold must not be toggled back off by the duplicate")
        XCTAssertEqual(
            RichTextMarkdownConverter.markdown(from: textView.attributedText),
            markdownAfterFirst,
            "a re-delivered action must never re-apply / duplicate markers"
        )
        XCTAssertNil(coordinator.pendingFormatAction)
    }

    @MainActor
    func testNewerFormatActionIDIsStillApplied() {
        let (coordinator, textView) = makeEditor(markdown: "hello")
        textView.selectedRange = NSRange(location: 0, length: 5)

        coordinator.stagePendingFormatAction(PendingFormatAction(id: 1, action: .bold))
        coordinator.applyPendingFormatActionIfNeeded(to: textView)
        // A genuine second tap (new id) must toggle bold off again.
        coordinator.stagePendingFormatAction(PendingFormatAction(id: 2, action: .bold))
        let applied = coordinator.applyPendingFormatActionIfNeeded(to: textView)

        XCTAssertTrue(applied)
        XCTAssertEqual(coordinator.consumedFormatActionID, 2)
        XCTAssertFalse(isBold(textView, at: 0))
    }

    @MainActor
    private func isBold(_ textView: UITextView, at index: Int) -> Bool {
        guard let font = textView.attributedText.attribute(.font, at: index, effectiveRange: nil) as? UIFont else {
            return false
        }
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
    }

    // MARK: - ownership flag

    @MainActor
    func testExternalSetReplacesContentWhenNotExporting() {
        // Regression: draft open / autosave restore (binding changes from outside, no export
        // in flight) must still replace the editor's text.
        let (coordinator, textView) = makeEditor(markdown: "old")

        coordinator.importExternalMarkdownIfNeeded(newMarkdown: "restored draft", current: "old")
        XCTAssertEqual(textView.attributedText.string, "restored draft")
    }

    @MainActor
    func testLocalMutationHoldsOwnershipUntilEveryExportLands() async {
        let (coordinator, textView) = makeEditor(markdown: "a")
        XCTAssertFalse(coordinator.isExporting)

        // Two rapid local mutations => two exports in flight.
        textView.selectedRange = NSRange(location: 1, length: 0)
        coordinator.stagePendingEdit(PendingComposerEdit(id: 1, insert: "b"))
        coordinator.applyPendingEditIfNeeded(to: textView)
        coordinator.stagePendingEdit(PendingComposerEdit(id: 2, insert: "c"))
        coordinator.applyPendingEditIfNeeded(to: textView)

        XCTAssertTrue(coordinator.isExporting, "un-exported local mutations block external imports")
        // Binding still holds the pre-edit value: the stale echo must not wipe the typed text.
        coordinator.importExternalMarkdownIfNeeded(newMarkdown: "a", current: "abc")
        XCTAssertEqual(textView.attributedText.string, "abc")

        await drainMainQueue()
        XCTAssertFalse(coordinator.isExporting, "released once all exports landed")
    }
}
