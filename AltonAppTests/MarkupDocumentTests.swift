import XCTest
@testable import AltonApp

final class MarkupDocumentTests: XCTestCase {
    func testUndoRedoStroke() {
        var doc = MarkupDocument()
        let stroke = MarkupStroke(
            brush: .pen,
            widthNorm: 0.02,
            colorHex: "#FFFFFF",
            points: [MarkupPoint(x: 0.1, y: 0.1), MarkupPoint(x: 0.2, y: 0.2)]
        )
        doc.appendStroke(stroke)
        XCTAssertEqual(doc.strokes.count, 1)
        XCTAssertTrue(doc.canUndo)
        doc.undo()
        XCTAssertTrue(doc.strokes.isEmpty)
        XCTAssertTrue(doc.canRedo)
        doc.redo()
        XCTAssertEqual(doc.strokes.count, 1)
    }

    func testHistoryLimit() {
        var doc = MarkupDocument()
        for i in 0..<(MarkupDocument.maxHistory + 10) {
            doc.appendStroke(
                MarkupStroke(
                    brush: .pen,
                    widthNorm: 0.01,
                    colorHex: "#FF0000",
                    points: [MarkupPoint(x: CGFloat(i) / 1000, y: 0.5)]
                )
            )
        }
        var undoCount = 0
        while doc.canUndo {
            doc.undo()
            undoCount += 1
        }
        XCTAssertEqual(undoCount, MarkupDocument.maxHistory)
    }

    func testRemoveText() {
        var doc = MarkupDocument()
        let item = MarkupTextItem(text: "Hello")
        doc.upsertText(item)
        XCTAssertEqual(doc.texts.count, 1)
        doc.removeText(id: item.id)
        XCTAssertTrue(doc.texts.isEmpty)
        doc.undo()
        XCTAssertEqual(doc.texts.count, 1)
    }

    func testUpdateTextTransformCommitsHistory() {
        var doc = MarkupDocument()
        let item = MarkupTextItem(text: "A", center: MarkupPoint(x: 0.5, y: 0.5))
        doc.upsertText(item)
        doc.updateTextTransform(
            id: item.id,
            center: MarkupPoint(x: 0.2, y: 0.3),
            scale: 1.5,
            rotation: 0.5
        )
        XCTAssertEqual(doc.texts.first?.center.x ?? 0, 0.2, accuracy: 0.001)
        doc.undo()
        XCTAssertEqual(doc.texts.first?.center.x ?? 0, 0.5, accuracy: 0.001)
    }

    /// One combined gesture commit → one undo step (pan+pinch+rotation coalesce).
    func testSingleTransformCommitIsOneUndoStep() {
        var doc = MarkupDocument()
        let item = MarkupTextItem(text: "A", center: MarkupPoint(x: 0.5, y: 0.5), scale: 1, rotation: 0)
        doc.upsertText(item)
        // Simulate end of simultaneous gesture: one update with all three values.
        doc.updateTextTransform(
            id: item.id,
            center: MarkupPoint(x: 0.4, y: 0.6),
            scale: 1.8,
            rotation: 0.3
        )
        XCTAssertEqual(doc.texts.first?.scale ?? 0, 1.8, accuracy: 0.001)
        XCTAssertEqual(doc.texts.first?.rotation ?? 0, 0.3, accuracy: 0.001)
        doc.undo()
        XCTAssertEqual(doc.texts.first?.scale ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(doc.texts.first?.rotation ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(doc.texts.first?.center.x ?? 0, 0.5, accuracy: 0.001)
        // Second undo removes the text itself.
        doc.undo()
        XCTAssertTrue(doc.texts.isEmpty)
    }
}
