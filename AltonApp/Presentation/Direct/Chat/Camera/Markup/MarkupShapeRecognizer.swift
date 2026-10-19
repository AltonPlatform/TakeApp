import CoreGraphics
import Foundation

/// Turns a freehand pen stroke into a straight shape when the gesture is close
/// to a line, arrow, rectangle, ellipse, triangle, or star.
enum MarkupShapeRecognizer {
    static func recognize(points: [CGPoint], canvasSize: CGSize) -> MarkupVectorShape? {
        guard points.count >= 8, canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        let length = pathLength(points)
        guard length >= 36 else { return nil }

        let sampled = resample(points, count: 64)
        let box = bounds(of: sampled)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= 28 else { return nil }

        let gap = hypot(sampled[0].x - sampled[sampled.count - 1].x, sampled[0].y - sampled[sampled.count - 1].y)
        let closed = gap < diagonal * 0.28
        let cornerIndexes = corners(in: sampled, closed: closed)

        if closed {
            if cornerIndexes.count == 3 {
                return triangle(sampled, corners: cornerIndexes, canvasSize: canvasSize)
            }
            if cornerIndexes.count == 4, isRectangular(sampled, corners: cornerIndexes) {
                return rectangle(sampled, corners: cornerIndexes, canvasSize: canvasSize)
            }
            if cornerIndexes.count == 5 || cornerIndexes.count == 10,
               isSpiky(sampled, corners: cornerIndexes) {
                return star(sampled, corners: cornerIndexes, canvasSize: canvasSize)
            }
            if cornerIndexes.count <= 1, let ellipse = ellipse(sampled, canvasSize: canvasSize) {
                return ellipse
            }
            return nil
        }

        if let arrow = arrow(sampled, canvasSize: canvasSize) {
            return arrow
        }
        if cornerIndexes.isEmpty, let line = line(sampled, canvasSize: canvasSize) {
            return line
        }
        return nil
    }

    // MARK: - Shapes

    private static func line(_ points: [CGPoint], canvasSize: CGSize) -> MarkupVectorShape? {
        let start = points[0]
        let end = points[points.count - 1]
        let chord = hypot(end.x - start.x, end.y - start.y)
        guard chord >= 32, maxDeviation(points, from: start, to: end) / chord < 0.1 else { return nil }
        return segment(from: start, to: end, kind: .line, canvasSize: canvasSize)
    }

    private static func arrow(_ points: [CGPoint], canvasSize: CGSize) -> MarkupVectorShape? {
        let start = points[0]
        var tipDistance: CGFloat = 0
        for point in points {
            tipDistance = max(tipDistance, hypot(point.x - start.x, point.y - start.y))
        }
        // First arrival at the tip. A later revisit (the head drawn back over it) must not
        // pull the shaft through the arrowhead.
        let tipIndex = points.firstIndex {
            hypot($0.x - start.x, $0.y - start.y) >= tipDistance - 4
        } ?? 0
        guard tipDistance >= 40, tipIndex > 4, tipIndex < points.count - 3 else { return nil }
        let after = CGFloat(points.count - 1 - tipIndex) / CGFloat(points.count)
        guard after > 0.1, after < 0.5 else { return nil }

        let tip = points[tipIndex]
        let end = points[points.count - 1]
        let endToTip = hypot(end.x - tip.x, end.y - tip.y)
        let endToStart = hypot(end.x - start.x, end.y - start.y)
        guard endToTip < tipDistance * 0.5, endToTip < endToStart else { return nil }

        let shaft = Array(points[0...tipIndex])
        let bow = signedBend(shaft, from: start, to: tip)
        guard abs(bow) / tipDistance < 0.6, shaftIsSmooth(shaft) else { return nil }
        var shape = segment(from: start, to: tip, kind: .arrow, canvasSize: canvasSize)
        shape.bend = bow / canvasSize.width
        return shape
    }

    private static func segment(
        from start: CGPoint,
        to end: CGPoint,
        kind: MarkupVectorShape.Kind,
        canvasSize: CGSize
    ) -> MarkupVectorShape {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return MarkupVectorShape(
            kind: kind,
            center: normalized(CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), canvasSize: canvasSize),
            width: hypot(dx, dy) / canvasSize.width,
            height: 0,
            rotation: atan2(dy, dx)
        )
    }

    private static func rectangle(
        _ points: [CGPoint],
        corners: [Int],
        canvasSize: CGSize
    ) -> MarkupVectorShape {
        let ordered = corners.map { points[$0] }
        let side0 = hypot(ordered[1].x - ordered[0].x, ordered[1].y - ordered[0].y)
        let side1 = hypot(ordered[2].x - ordered[1].x, ordered[2].y - ordered[1].y)
        let side2 = hypot(ordered[3].x - ordered[2].x, ordered[3].y - ordered[2].y)
        let side3 = hypot(ordered[0].x - ordered[3].x, ordered[0].y - ordered[3].y)
        let width = (side0 + side2) / 2
        let height = (side1 + side3) / 2
        let center = centroid(ordered)
        let rotation = atan2(ordered[1].y - ordered[0].y, ordered[1].x - ordered[0].x)
        return MarkupVectorShape(
            kind: .rectangle,
            center: normalized(center, canvasSize: canvasSize),
            width: width / canvasSize.width,
            height: height / canvasSize.height,
            rotation: rotation
        )
    }

    private static func triangle(
        _ points: [CGPoint],
        corners: [Int],
        canvasSize: CGSize
    ) -> MarkupVectorShape {
        let ordered = corners.map { points[$0] }
        let edges = [
            (hypot(ordered[1].x - ordered[0].x, ordered[1].y - ordered[0].y), 0, 1, 2),
            (hypot(ordered[2].x - ordered[1].x, ordered[2].y - ordered[1].y), 1, 2, 0),
            (hypot(ordered[0].x - ordered[2].x, ordered[0].y - ordered[2].y), 2, 0, 1)
        ]
        let base = edges.max(by: { $0.0 < $1.0 }) ?? edges[0]
        let a = ordered[base.1]
        let b = ordered[base.2]
        let apex = ordered[base.3]
        let width = base.0
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(width, 1)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let altitude = (apex.x - a.x) * normal.x + (apex.y - a.y) * normal.y
        let height = abs(altitude)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let center = CGPoint(
            x: mid.x + normal.x * altitude / 2,
            y: mid.y + normal.y * altitude / 2
        )
        return MarkupVectorShape(
            kind: .triangle,
            center: normalized(center, canvasSize: canvasSize),
            width: width / canvasSize.width,
            height: height / canvasSize.height,
            rotation: atan2(dy, dx)
        )
    }

    private static func star(
        _ points: [CGPoint],
        corners: [Int],
        canvasSize: CGSize
    ) -> MarkupVectorShape {
        let center = centroid(points)
        let outer = corners.map { points[$0] }
        let radii = outer.map { hypot($0.x - center.x, $0.y - center.y) }
        let radius = radii.max() ?? 1
        let first = outer.max(by: { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }) ?? outer[0]
        let rotation = atan2(first.y - center.y, first.x - center.x) + .pi / 2
        let diameter = radius * 2
        return MarkupVectorShape(
            kind: .star,
            center: normalized(center, canvasSize: canvasSize),
            width: diameter / canvasSize.width,
            height: diameter / canvasSize.height,
            rotation: rotation
        )
    }

    private static func ellipse(_ points: [CGPoint], canvasSize: CGSize) -> MarkupVectorShape? {
        let count = CGFloat(points.count)
        let center = centroid(points)
        var xx: CGFloat = 0
        var xy: CGFloat = 0
        var yy: CGFloat = 0
        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            xx += dx * dx
            xy += dx * dy
            yy += dy * dy
        }
        xx /= count
        xy /= count
        yy /= count
        let trace = xx + yy
        let det = xx * yy - xy * xy
        let disc = sqrt(max(0, trace * trace / 4 - det))
        let major = max(trace / 2 + disc, 0)
        let minor = max(trace / 2 - disc, 0)
        let halfW = sqrt(major) * sqrt(2)
        let halfH = sqrt(minor) * sqrt(2)
        guard halfW > 8, halfH > 8 else { return nil }
        let rotation = 0.5 * atan2(2 * xy, xx - yy)

        let cosR = cos(rotation)
        let sinR = sin(rotation)
        var error: CGFloat = 0
        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let localX = dx * cosR + dy * sinR
            let localY = -dx * sinR + dy * cosR
            let value = (localX * localX) / (halfW * halfW) + (localY * localY) / (halfH * halfH)
            error += abs(1 - value)
        }
        error /= count
        guard error < 0.28 else { return nil }
        return MarkupVectorShape(
            kind: .ellipse,
            center: normalized(center, canvasSize: canvasSize),
            width: (halfW * 2) / canvasSize.width,
            height: (halfH * 2) / canvasSize.height,
            rotation: rotation
        )
    }

    // MARK: - Geometry

    private static func corners(in points: [CGPoint], closed: Bool) -> [Int] {
        let count = points.count
        let window = max(2, count / 18)
        guard count > window * 2 else { return [] }
        var candidates: [(index: Int, turn: CGFloat)] = []
        let start = closed ? 0 : window
        let end = closed ? count : count - window
        for index in start..<end {
            let previous = points[(index - window + count) % count]
            let current = points[index % count]
            let next = points[(index + window) % count]
            let turn = turnAngle(previous, current, next)
            if turn > 0.7 {
                candidates.append((index % count, turn))
            }
        }
        candidates.sort { $0.turn > $1.turn }
        var kept: [Int] = []
        let separation = max(4, count / 10)
        for candidate in candidates {
            let crowded = kept.contains { existing in
                circularDistance(existing, candidate.index, count: count, closed: closed) < separation
            }
            if !crowded {
                kept.append(candidate.index)
            }
        }
        return kept.sorted()
    }

    private static func isRectangular(_ points: [CGPoint], corners: [Int]) -> Bool {
        guard corners.count == 4 else { return false }
        for index in corners.indices {
            let previous = points[corners[(index + 3) % 4]]
            let current = points[corners[index]]
            let next = points[corners[(index + 1) % 4]]
            let turn = turnAngle(previous, current, next)
            if turn < 0.85 || turn > 2.1 { return false }
        }
        return true
    }

    private static func isSpiky(_ points: [CGPoint], corners: [Int]) -> Bool {
        guard corners.count >= 5 else { return false }
        let center = centroid(points)
        let radii = corners
            .map { hypot(points[$0].x - center.x, points[$0].y - center.y) }
            .sorted()
        guard let high = radii.last, high > 8 else { return false }
        if corners.count >= 8, radii.count >= 2 {
            let half = radii.count / 2
            let innerMean = radii.prefix(half).reduce(0, +) / CGFloat(half)
            let outerMean = radii.suffix(half).reduce(0, +) / CGFloat(radii.count - half)
            return innerMean < outerMean * 0.72
        }
        var inner: [CGFloat] = []
        for index in corners.indices {
            let start = corners[index]
            let end = corners[(index + 1) % corners.count]
            let mid = midpointIndex(from: start, to: end, count: points.count)
            inner.append(hypot(points[mid].x - center.x, points[mid].y - center.y))
        }
        let outerMean = radii.reduce(0, +) / CGFloat(radii.count)
        let innerMean = inner.reduce(0, +) / CGFloat(inner.count)
        return innerMean < outerMean * 0.75
    }

    private static func midpointIndex(from start: Int, to end: Int, count: Int) -> Int {
        let distance = (end - start + count) % count
        return (start + max(distance / 2, 1)) % count
    }

    private static func circularDistance(_ a: Int, _ b: Int, count: Int, closed: Bool) -> Int {
        let raw = abs(a - b)
        return closed ? min(raw, count - raw) : raw
    }

    private static func turnAngle(_ previous: CGPoint, _ current: CGPoint, _ next: CGPoint) -> CGFloat {
        let ax = current.x - previous.x
        let ay = current.y - previous.y
        let bx = next.x - current.x
        let by = next.y - current.y
        let dot = ax * bx + ay * by
        let cross = ax * by - ay * bx
        return abs(atan2(cross, dot))
    }

    /// Largest signed distance from the chord. Positive is to the left of start→end.
    private static func signedBend(_ points: [CGPoint], from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        var best: CGFloat = 0
        for point in points {
            let signed = (dx * (point.y - start.y) - dy * (point.x - start.x)) / length
            if abs(signed) > abs(best) {
                best = signed
            }
        }
        return best
    }

    private static func shaftIsSmooth(_ points: [CGPoint]) -> Bool {
        guard points.count > 8 else { return true }
        let window = max(2, points.count / 12)
        let last = min(points.count - window - 1, Int(CGFloat(points.count) * 0.82))
        guard window < last else { return true }
        for index in window..<last {
            let turn = turnAngle(points[index - window], points[index], points[index + window])
            if turn > 1.05 { return false }
        }
        return true
    }

    private static func maxDeviation(_ points: [CGPoint], from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        var maxDistance: CGFloat = 0
        for point in points {
            let distance = abs((point.x - start.x) * dy - (point.y - start.y) * dx) / length
            maxDistance = max(maxDistance, distance)
        }
        return maxDistance
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        let x = points.reduce(CGFloat(0)) { $0 + $1.x } / count
        let y = points.reduce(CGFloat(0)) { $0 + $1.y } / count
        return CGPoint(x: x, y: y)
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            length += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return length
    }

    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, count > 1 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return points }
        let step = total / CGFloat(count - 1)
        var result: [CGPoint] = [points[0]]
        var traveled: CGFloat = 0
        var index = 1
        var nextMark = step
        while result.count < count && index < points.count {
            let segment = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            if traveled + segment >= nextMark {
                let remain = nextMark - traveled
                let t = segment > 0 ? remain / segment : 0
                let point = CGPoint(
                    x: points[index - 1].x + (points[index].x - points[index - 1].x) * t,
                    y: points[index - 1].y + (points[index].y - points[index - 1].y) * t
                )
                result.append(point)
                nextMark += step
            } else {
                traveled += segment
                index += 1
            }
        }
        while result.count < count {
            result.append(points[points.count - 1])
        }
        return result
    }

    private static func normalized(_ point: CGPoint, canvasSize: CGSize) -> MarkupPoint {
        MarkupPoint(
            x: point.x / canvasSize.width,
            y: point.y / canvasSize.height
        )
    }
}
