import XCTest
@testable import AltonApp

final class MarkupShapeRecognizerTests: XCTestCase {
    private let canvas = CGSize(width: 400, height: 600)

    func testCircleBecomesEllipse() {
        let shape = MarkupShapeRecognizer.recognize(points: circle(center: CGPoint(x: 180, y: 220), radius: 70), canvasSize: canvas)
        XCTAssertEqual(shape?.kind, .ellipse)
    }

    func testRectangle() {
        let shape = MarkupShapeRecognizer.recognize(
            points: polygon([
                CGPoint(x: 40, y: 80),
                CGPoint(x: 220, y: 80),
                CGPoint(x: 220, y: 190),
                CGPoint(x: 40, y: 190)
            ]),
            canvasSize: canvas
        )
        XCTAssertEqual(shape?.kind, .rectangle)
    }

    func testTriangle() {
        let shape = MarkupShapeRecognizer.recognize(
            points: polygon([
                CGPoint(x: 160, y: 40),
                CGPoint(x: 280, y: 200),
                CGPoint(x: 40, y: 200)
            ]),
            canvasSize: canvas
        )
        XCTAssertEqual(shape?.kind, .triangle)
    }

    func testStar() {
        var tips: [CGPoint] = []
        let center = CGPoint(x: 200, y: 240)
        for index in 0..<10 {
            let radius: CGFloat = index.isMultiple(of: 2) ? 80 : 32
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            tips.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        let shape = MarkupShapeRecognizer.recognize(points: polygon(tips), canvasSize: canvas)
        XCTAssertEqual(shape?.kind, .star)
    }

    func testStraightLine() {
        let shape = MarkupShapeRecognizer.recognize(
            points: samples(from: CGPoint(x: 30, y: 100), to: CGPoint(x: 300, y: 140), count: 24),
            canvasSize: canvas
        )
        XCTAssertEqual(shape?.kind, .line)
    }

    func testArrow() {
        var points = samples(from: CGPoint(x: 40, y: 200), to: CGPoint(x: 260, y: 200), count: 28)
        points.append(contentsOf: samples(from: CGPoint(x: 260, y: 200), to: CGPoint(x: 210, y: 160), count: 8))
        points.append(contentsOf: samples(from: CGPoint(x: 210, y: 160), to: CGPoint(x: 260, y: 200), count: 4))
        points.append(contentsOf: samples(from: CGPoint(x: 260, y: 200), to: CGPoint(x: 210, y: 240), count: 8))
        let shape = MarkupShapeRecognizer.recognize(points: points, canvasSize: canvas)
        XCTAssertEqual(shape?.kind, .arrow)
        XCTAssertEqual(shape?.bend ?? 1, 0, accuracy: 0.02)
    }

    func testCurvedArrowKeepsTheBend() {
        let start = CGPoint(x: 40, y: 280)
        let tip = CGPoint(x: 280, y: 280)
        var points: [CGPoint] = (0..<28).map { index in
            let t = CGFloat(index) / 27
            let x = start.x + (tip.x - start.x) * t
            let y = start.y - sin(t * .pi) * 70
            return CGPoint(x: x, y: y)
        }
        points.append(contentsOf: samples(from: tip, to: CGPoint(x: 230, y: 240), count: 8))
        points.append(contentsOf: samples(from: CGPoint(x: 230, y: 240), to: tip, count: 4))
        points.append(contentsOf: samples(from: tip, to: CGPoint(x: 230, y: 320), count: 8))
        let shape = MarkupShapeRecognizer.recognize(points: points, canvasSize: canvas)
        XCTAssertEqual(shape?.kind, .arrow)
        XCTAssertLessThan(shape?.bend ?? 0, -0.05)
    }

    func testScribbleStaysFreehand() {
        var points: [CGPoint] = []
        for index in 0..<20 {
            let x = 40 + CGFloat(index) * 12
            let y: CGFloat = index.isMultiple(of: 2) ? 80 : 180
            points.append(CGPoint(x: x, y: y))
        }
        let shape = MarkupShapeRecognizer.recognize(points: samples(along: points, count: 8), canvasSize: canvas)
        XCTAssertNil(shape)
    }

    private func circle(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...48).map { index in
            let angle = CGFloat(index) / 48 * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private func polygon(_ corners: [CGPoint]) -> [CGPoint] {
        var points: [CGPoint] = []
        let closed = corners + [corners[0]]
        for index in 0..<(closed.count - 1) {
            points.append(contentsOf: samples(from: closed[index], to: closed[index + 1], count: 12).dropLast())
        }
        points.append(corners[0])
        return points
    }

    private func samples(from start: CGPoint, to end: CGPoint, count: Int) -> [CGPoint] {
        guard count > 1 else { return [start, end] }
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1)
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    private func samples(along corners: [CGPoint], count: Int) -> [CGPoint] {
        var points: [CGPoint] = []
        for index in 0..<(corners.count - 1) {
            points.append(contentsOf: samples(from: corners[index], to: corners[index + 1], count: count).dropLast())
        }
        if let last = corners.last {
            points.append(last)
        }
        return points
    }
}
