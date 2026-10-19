import XCTest
@testable import AltonApp

final class ChatPhotoLibraryModelTests: XCTestCase {
    func testCellSideIsSquareThirdOfTheRow() {
        let side = ChatAttachGrid.cellSide(containerWidth: 302, columns: 3, spacing: 2)
        XCTAssertEqual(side, 99)
    }

    func testThumbPixelSizeScalesTheSquare() {
        let size = ChatAttachGrid.thumbPixelSize(containerWidth: 302, scale: 3, columns: 3, spacing: 2)
        XCTAssertEqual(size.width, size.height)
        XCTAssertEqual(size.width, 297)
    }

    func testZeroWidthProducesZero() {
        XCTAssertEqual(ChatAttachGrid.cellSide(containerWidth: 0), 0)
        XCTAssertEqual(ChatAttachGrid.thumbPixelSize(containerWidth: 0, scale: 2), .zero)
    }
}
