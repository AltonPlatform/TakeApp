import Foundation

/// Immutable QR module grid. Pure Swift — no CoreImage / Metal / AGX.
struct QRMatrix: Equatable {
    let size: Int
    private let modules: [Bool]

    init(size: Int, modules: [Bool]) {
        precondition(modules.count == size * size)
        self.size = size
        self.modules = modules
    }

    func isDark(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return modules[y * size + x]
    }
}

/// Byte-mode QR encoder, ECC level M, versions 1…10.
/// Enough for Take share URLs (~40–80 UTF-8 bytes) without any GPU path.
enum QRCodeEncoder {
    /// Encodes `string` as UTF-8 byte-mode QR. Returns `nil` if the payload
    /// exceeds version-10 / ECC-M capacity (~213 bytes).
    static func encode(_ string: String) -> QRMatrix? {
        let data = Array(string.utf8)
        guard let version = smallestVersion(forByteCount: data.count) else { return nil }
        return encode(bytes: data, version: version)
    }

    // MARK: - Version / capacity (ECC-M, byte mode)

    /// Max UTF-8 byte length per version at ECC-M (ISO 18004 Table 7).
    private static let byteCapacityM: [Int] = [
        0, 14, 26, 42, 62, 84, 106, 122, 152, 180, 213,
    ]

    private static func smallestVersion(forByteCount count: Int) -> Int? {
        for version in 1...10 where byteCapacityM[version] >= count {
            return version
        }
        return nil
    }

    /// Block layout for ECC-M: (numBlocks, dataCodewordsPerBlock, ecCodewordsPerBlock)
    /// Versions with two groups appear as two tuples.
    private static func blockInfo(version: Int) -> [(blocks: Int, data: Int, ec: Int)] {
        switch version {
        case 1: return [(1, 16, 10)]
        case 2: return [(1, 28, 16)]
        case 3: return [(1, 44, 26)]
        case 4: return [(2, 32, 18)]
        case 5: return [(2, 43, 24)]
        case 6: return [(4, 27, 16)]
        case 7: return [(4, 31, 18)]
        case 8: return [(2, 38, 22), (2, 39, 22)]
        case 9: return [(3, 36, 22), (2, 37, 22)]
        case 10: return [(4, 43, 26), (1, 44, 26)]
        default: return []
        }
    }

    private static func moduleCount(version: Int) -> Int {
        21 + (version - 1) * 4
    }

    private static let alignmentCenters: [[Int]] = [
        [],
        [],
        [6, 18],
        [6, 22],
        [6, 26],
        [6, 30],
        [6, 34],
        [6, 22, 38],
        [6, 24, 42],
        [6, 26, 46],
        [6, 28, 50],
    ]

    // MARK: - Encode pipeline

    private static func encode(bytes: [UInt8], version: Int) -> QRMatrix {
        let codewords = makeDataCodewords(bytes: bytes, version: version)
        let finalCodewords = interleaveWithEC(dataCodewords: codewords, version: version)
        let size = moduleCount(version: version)

        var bestModules: [Bool]?
        var bestPenalty = Int.max
        for mask in 0..<8 {
            var modules = [Bool](repeating: false, count: size * size)
            var reserved = [Bool](repeating: false, count: size * size)
            placeFunctionPatterns(
                modules: &modules,
                reserved: &reserved,
                size: size,
                version: version
            )
            placeData(
                codewords: finalCodewords,
                modules: &modules,
                reserved: reserved,
                size: size,
                mask: mask
            )
            placeFormatBits(modules: &modules, reserved: &reserved, size: size, mask: mask)
            if version >= 7 {
                placeVersionBits(modules: &modules, size: size, version: version)
            }
            let penalty = maskPenalty(modules: modules, size: size)
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestModules = modules
            }
        }
        return QRMatrix(size: size, modules: bestModules!)
    }

    // MARK: - Data bits → codewords

    private static func makeDataCodewords(bytes: [UInt8], version: Int) -> [UInt8] {
        let totalData = blockInfo(version: version).reduce(0) { $0 + $1.blocks * $1.data }
        var bits = BitBuffer()
        bits.append(0b0100, length: 4) // byte mode
        let charCountBits = version <= 9 ? 8 : 16
        bits.append(bytes.count, length: charCountBits)
        for byte in bytes {
            bits.append(Int(byte), length: 8)
        }
        // Terminator (up to 4 zero bits).
        let capacityBits = totalData * 8
        let terminator = min(4, capacityBits - bits.count)
        if terminator > 0 {
            bits.append(0, length: terminator)
        }
        // Pad to byte boundary.
        while bits.count % 8 != 0 {
            bits.append(0, length: 1)
        }
        // Pad codewords 0xEC / 0x11.
        var padToggle = true
        while bits.count / 8 < totalData {
            bits.append(padToggle ? 0xEC : 0x11, length: 8)
            padToggle.toggle()
        }
        return bits.toBytes()
    }

    private static func interleaveWithEC(dataCodewords: [UInt8], version: Int) -> [UInt8] {
        let groups = blockInfo(version: version)
        var dataBlocks: [[UInt8]] = []
        var ecBlocks: [[UInt8]] = []
        var offset = 0
        for group in groups {
            for _ in 0..<group.blocks {
                let data = Array(dataCodewords[offset..<(offset + group.data)])
                offset += group.data
                dataBlocks.append(data)
                ecBlocks.append(ReedSolomon.encode(data: data, ecCount: group.ec))
            }
        }
        var result: [UInt8] = []
        let maxData = dataBlocks.map(\.count).max() ?? 0
        for i in 0..<maxData {
            for block in dataBlocks where i < block.count {
                result.append(block[i])
            }
        }
        let maxEC = ecBlocks.map(\.count).max() ?? 0
        for i in 0..<maxEC {
            for block in ecBlocks where i < block.count {
                result.append(block[i])
            }
        }
        return result
    }

    // MARK: - Function patterns

    private static func placeFunctionPatterns(
        modules: inout [Bool],
        reserved: inout [Bool],
        size: Int,
        version: Int
    ) {
        placeFinder(modules: &modules, reserved: &reserved, size: size, left: 0, top: 0)
        placeFinder(modules: &modules, reserved: &reserved, size: size, left: size - 7, top: 0)
        placeFinder(modules: &modules, reserved: &reserved, size: size, left: 0, top: size - 7)

        // Separators (light) around finders.
        for i in 0..<8 {
            set(modules: &modules, reserved: &reserved, size: size, x: 7, y: i, dark: false, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: i, y: 7, dark: false, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: size - 8, y: i, dark: false, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: size - 8 + i, y: 7, dark: false, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: 7, y: size - 8 + i, dark: false, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: i, y: size - 8, dark: false, reserve: true)
        }

        // Timing patterns.
        for i in 8..<(size - 8) {
            let dark = i % 2 == 0
            set(modules: &modules, reserved: &reserved, size: size, x: i, y: 6, dark: dark, reserve: true)
            set(modules: &modules, reserved: &reserved, size: size, x: 6, y: i, dark: dark, reserve: true)
        }

        // Alignment patterns.
        let centers = alignmentCenters[version]
        for cy in centers {
            for cx in centers {
                if (cx == 6 && cy == 6)
                    || (cx == 6 && cy == size - 7)
                    || (cx == size - 7 && cy == 6) {
                    continue
                }
                placeAlignment(modules: &modules, reserved: &reserved, size: size, cx: cx, cy: cy)
            }
        }

        // Dark module (always at (8, 4*version+9)).
        set(
            modules: &modules,
            reserved: &reserved,
            size: size,
            x: 8,
            y: 4 * version + 9,
            dark: true,
            reserve: true
        )

        // Reserve format-info areas (filled later).
        for i in 0..<9 {
            reserveOnly(&reserved, size: size, x: i, y: 8)
            reserveOnly(&reserved, size: size, x: 8, y: i)
        }
        for i in 0..<8 {
            reserveOnly(&reserved, size: size, x: size - 1 - i, y: 8)
            reserveOnly(&reserved, size: size, x: 8, y: size - 1 - i)
        }

        // Reserve version-info areas (versions ≥ 7).
        if version >= 7 {
            for i in 0..<6 {
                for j in 0..<3 {
                    reserveOnly(&reserved, size: size, x: i, y: size - 11 + j)
                    reserveOnly(&reserved, size: size, x: size - 11 + j, y: i)
                }
            }
        }
    }

    private static func placeFinder(
        modules: inout [Bool],
        reserved: inout [Bool],
        size: Int,
        left: Int,
        top: Int
    ) {
        for dy in 0..<7 {
            for dx in 0..<7 {
                let onBorder = dx == 0 || dx == 6 || dy == 0 || dy == 6
                let inCenter = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4
                set(
                    modules: &modules,
                    reserved: &reserved,
                    size: size,
                    x: left + dx,
                    y: top + dy,
                    dark: onBorder || inCenter,
                    reserve: true
                )
            }
        }
    }

    private static func placeAlignment(
        modules: inout [Bool],
        reserved: inout [Bool],
        size: Int,
        cx: Int,
        cy: Int
    ) {
        for dy in -2...2 {
            for dx in -2...2 {
                let dark = abs(dx) == 2 || abs(dy) == 2 || (dx == 0 && dy == 0)
                set(
                    modules: &modules,
                    reserved: &reserved,
                    size: size,
                    x: cx + dx,
                    y: cy + dy,
                    dark: dark,
                    reserve: true
                )
            }
        }
    }

    private static func placeData(
        codewords: [UInt8],
        modules: inout [Bool],
        reserved: [Bool],
        size: Int,
        mask: Int
    ) {
        var bitIndex = 0
        let totalBits = codewords.count * 8
        var x = size - 1
        var upward = true
        while x > 0 {
            if x == 6 { x -= 1 }
            let yRange = upward ? stride(from: size - 1, through: 0, by: -1)
                : stride(from: 0, through: size - 1, by: 1)
            for y in yRange {
                for dx in 0...1 {
                    let px = x - dx
                    let idx = y * size + px
                    if reserved[idx] { continue }
                    var dark = false
                    if bitIndex < totalBits {
                        let byte = codewords[bitIndex / 8]
                        let bit = 7 - (bitIndex % 8)
                        dark = ((byte >> bit) & 1) == 1
                        bitIndex += 1
                    }
                    if maskBit(mask: mask, x: px, y: y) {
                        dark.toggle()
                    }
                    modules[idx] = dark
                }
            }
            upward.toggle()
            x -= 2
        }
    }

    private static func maskBit(mask: Int, x: Int, y: Int) -> Bool {
        switch mask {
        case 0: return (x + y) % 2 == 0
        case 1: return y % 2 == 0
        case 2: return x % 3 == 0
        case 3: return (x + y) % 3 == 0
        case 4: return (y / 2 + x / 3) % 2 == 0
        case 5: return (x * y) % 2 + (x * y) % 3 == 0
        case 6: return ((x * y) % 2 + (x * y) % 3) % 2 == 0
        case 7: return ((x + y) % 2 + (x * y) % 3) % 2 == 0
        default: return false
        }
    }

    // MARK: - Format / version bits

    private static func placeFormatBits(
        modules: inout [Bool],
        reserved: inout [Bool],
        size: Int,
        mask: Int
    ) {
        // ECC-M = 00, then 3-bit mask → 5 data bits; BCH remainder → 15 bits total.
        let data = (0b00 << 3) | mask
        let bits = formatBits(data: data)
        // Primary copy (MSB → LSB). Skips timing at (6,8)/(8,6).
        let positions: [(Int, Int)] = [
            (0, 8), (1, 8), (2, 8), (3, 8), (4, 8), (5, 8), (7, 8), (8, 8),
            (8, 7), (8, 5), (8, 4), (8, 3), (8, 2), (8, 1), (8, 0),
        ]
        // Mirror: 8 horizontal + 7 vertical. (8, size-8) is the always-dark module — skip it.
        let mirror: [(Int, Int)] = [
            (size - 1, 8), (size - 2, 8), (size - 3, 8), (size - 4, 8),
            (size - 5, 8), (size - 6, 8), (size - 7, 8), (size - 8, 8),
            (8, size - 7), (8, size - 6), (8, size - 5),
            (8, size - 4), (8, size - 3), (8, size - 2), (8, size - 1),
        ]
        for i in 0..<15 {
            let dark = ((bits >> (14 - i)) & 1) == 1
            let (x1, y1) = positions[i]
            let (x2, y2) = mirror[i]
            modules[y1 * size + x1] = dark
            modules[y2 * size + x2] = dark
            reserved[y1 * size + x1] = true
            reserved[y2 * size + x2] = true
        }
    }

    /// BCH(15,5) format information with mask 0x5412.
    private static func formatBits(data: Int) -> Int {
        var rem = data << 10
        for i in stride(from: 4, through: 0, by: -1) {
            if (rem & (1 << (i + 10))) != 0 {
                rem ^= 0x537 << i
            }
        }
        return ((data << 10) | rem) ^ 0x5412
    }

    private static func placeVersionBits(modules: inout [Bool], size: Int, version: Int) {
        let bits = versionBits(version: version)
        for i in 0..<18 {
            let dark = ((bits >> i) & 1) == 1
            let a = i / 3
            let b = i % 3
            modules[(size - 11 + b) * size + a] = dark
            modules[a * size + (size - 11 + b)] = dark
        }
    }

    /// BCH(18,6) version information.
    private static func versionBits(version: Int) -> Int {
        var rem = version << 12
        for i in stride(from: 5, through: 0, by: -1) {
            if (rem & (1 << (i + 12))) != 0 {
                rem ^= 0x1F25 << i
            }
        }
        return (version << 12) | rem
    }

    // MARK: - Mask penalty (ISO 18004)

    private static func maskPenalty(modules: [Bool], size: Int) -> Int {
        var score = 0

        // N1: runs of 5+ same color in rows/cols.
        for y in 0..<size {
            var run = 1
            for x in 1..<size {
                if modules[y * size + x] == modules[y * size + x - 1] {
                    run += 1
                } else {
                    if run >= 5 { score += 3 + (run - 5) }
                    run = 1
                }
            }
            if run >= 5 { score += 3 + (run - 5) }
        }
        for x in 0..<size {
            var run = 1
            for y in 1..<size {
                if modules[y * size + x] == modules[(y - 1) * size + x] {
                    run += 1
                } else {
                    if run >= 5 { score += 3 + (run - 5) }
                    run = 1
                }
            }
            if run >= 5 { score += 3 + (run - 5) }
        }

        // N2: 2×2 blocks of same color.
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let v = modules[y * size + x]
                if v == modules[y * size + x + 1]
                    && v == modules[(y + 1) * size + x]
                    && v == modules[(y + 1) * size + x + 1] {
                    score += 3
                }
            }
        }

        // N3: finder-like patterns in rows/cols.
        let patternA: [Bool] = [true, false, true, true, true, false, true, false, false, false, false]
        let patternB: [Bool] = [false, false, false, false, true, false, true, true, true, false, true]
        for y in 0..<size {
            var row = [Bool]()
            row.reserveCapacity(size)
            for x in 0..<size { row.append(modules[y * size + x]) }
            score += 40 * countOccurrences(of: patternA, in: row)
            score += 40 * countOccurrences(of: patternB, in: row)
        }
        for x in 0..<size {
            var col = [Bool]()
            col.reserveCapacity(size)
            for y in 0..<size { col.append(modules[y * size + x]) }
            score += 40 * countOccurrences(of: patternA, in: col)
            score += 40 * countOccurrences(of: patternB, in: col)
        }

        // N4: dark-module ratio away from 50%.
        let darkCount = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = size * size
        let percent = (100 * darkCount) / total
        let k = abs(percent - 50) / 5
        score += k * 10

        return score
    }

    private static func countOccurrences(of pattern: [Bool], in sequence: [Bool]) -> Int {
        guard sequence.count >= pattern.count else { return 0 }
        var count = 0
        for i in 0...(sequence.count - pattern.count) {
            if Array(sequence[i..<(i + pattern.count)]) == pattern {
                count += 1
            }
        }
        return count
    }

    // MARK: - Grid helpers

    private static func set(
        modules: inout [Bool],
        reserved: inout [Bool],
        size: Int,
        x: Int,
        y: Int,
        dark: Bool,
        reserve: Bool
    ) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        let idx = y * size + x
        modules[idx] = dark
        if reserve { reserved[idx] = true }
    }

    private static func reserveOnly(_ reserved: inout [Bool], size: Int, x: Int, y: Int) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        reserved[y * size + x] = true
    }
}

// MARK: - Bit buffer

private struct BitBuffer {
    private(set) var count = 0
    private var bytes: [UInt8] = []

    mutating func append(_ value: Int, length: Int) {
        for i in stride(from: length - 1, through: 0, by: -1) {
            let bit = ((value >> i) & 1) != 0
            let byteIndex = count / 8
            if byteIndex >= bytes.count {
                bytes.append(0)
            }
            if bit {
                bytes[byteIndex] |= 1 << (7 - (count % 8))
            }
            count += 1
        }
    }

    func toBytes() -> [UInt8] { bytes }
}

// MARK: - Reed–Solomon over GF(256)

private enum ReedSolomon {
    /// Generator polynomial coefficients for `ecCount` parity symbols.
    private static func generator(_ ecCount: Int) -> [UInt8] {
        var poly: [UInt8] = [1]
        for i in 0..<ecCount {
            poly = multiply(poly, [1, GF.exp(i)])
        }
        return poly
    }

    private static func multiply(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: a.count + b.count - 1)
        for i in 0..<a.count {
            for j in 0..<b.count {
                result[i + j] ^= GF.mul(a[i], b[j])
            }
        }
        return result
    }

    static func encode(data: [UInt8], ecCount: Int) -> [UInt8] {
        let gen = generator(ecCount)
        var message = data + [UInt8](repeating: 0, count: ecCount)
        for i in 0..<data.count {
            let coef = message[i]
            if coef == 0 { continue }
            for j in 0..<gen.count {
                message[i + j] ^= GF.mul(gen[j], coef)
            }
        }
        return Array(message[data.count...])
    }
}

private enum GF {
    private static let expTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 512)
        var x: Int = 1
        for i in 0..<255 {
            table[i] = UInt8(x)
            x <<= 1
            if x >= 256 { x ^= 0x11D }
        }
        for i in 255..<512 {
            table[i] = table[i - 255]
        }
        return table
    }()

    private static let logTable: [Int] = {
        var table = [Int](repeating: 0, count: 256)
        for i in 0..<255 {
            table[Int(expTable[i])] = i
        }
        return table
    }()

    static func exp(_ i: Int) -> UInt8 {
        expTable[i]
    }

    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        if a == 0 || b == 0 { return 0 }
        return expTable[logTable[Int(a)] + logTable[Int(b)]]
    }
}
