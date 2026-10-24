// OfflineSchoolCityIndex.swift — ← data/jw/OfflineSchoolCityIndex.kt
// Local point-in-polygon lookup. Never guesses a city from its nearest centre.
//
// SCB1 二进制格式 (与 Android 1:1):
//   magic  int32  0x53434231 ("SCB1")
//   每个 area: nameLen int32(1..256) + name bytes(UTF-8) + polygonCount int32(1..10000)
//     每个 polygon: ringCount int32(1..10000)
//       每个 ring: pointCount int32(3..1000000) + 每点 (longitude int32, latitude int32)
//   坐标为 度×10000 的缩放整数; 总点数上限 2,000,000; EOF 后不得有尾随字节。

import Foundation
import Compression

final class OfflineSchoolCityIndex {
    private struct Ring {
        let coordinates: [Int32]     // [x0, y0, x1, y1, ...] 缩放整数(度×10000)
        let minX: Int32, maxX: Int32, minY: Int32, maxY: Int32

        init(coordinates: [Int32]) {
            self.coordinates = coordinates
            var left = Int32.max, right = Int32.min, bottom = Int32.max, top = Int32.min
            var i = 0
            while i < coordinates.count {
                left = min(left, coordinates[i])
                right = max(right, coordinates[i])
                bottom = min(bottom, coordinates[i + 1])
                top = max(top, coordinates[i + 1])
                i += 2
            }
            minX = left; maxX = right; minY = bottom; maxY = top
        }

        /// 射线法 point-in-polygon;边界上的点(叉积≈0 且在段内)算包含。
        func contains(x: Double, y: Double) -> Bool {
            if x < Double(minX) || x > Double(maxX) || y < Double(minY) || y > Double(maxY) {
                return false
            }
            var inside = false
            var previous = coordinates.count - 2
            var current = 0
            while current < coordinates.count {
                let ax = coordinates[previous]
                let ay = coordinates[previous + 1]
                let bx = coordinates[current]
                let by = coordinates[current + 1]
                let cross = (x - Double(ax)) * (Double(by) - Double(ay))
                    - (y - Double(ay)) * (Double(bx) - Double(ax))
                if abs(cross) < 1e-6 && x >= Double(min(ax, bx)) && x <= Double(max(ax, bx))
                    && y >= Double(min(ay, by)) && y <= Double(max(ay, by)) {
                    return true
                }
                if (Double(ay) > y) != (Double(by) > y)
                    && x < (Double(bx) - Double(ax)) * (y - Double(ay)) / (Double(by) - Double(ay)) + Double(ax) {
                    inside.toggle()
                }
                previous = current
                current += 2
            }
            return inside
        }
    }

    private struct Polygon {
        let rings: [Ring]
        func contains(x: Double, y: Double) -> Bool {
            guard let first = rings.first, first.contains(x: x, y: y) else { return false }
            for hole in rings.dropFirst() where hole.contains(x: x, y: y) { return false }
            return true
        }
    }

    private struct Area {
        let name: String
        let polygons: [Polygon]
    }

    private let areas: [Area]

    private init(areas: [Area]) {
        self.areas = areas
    }

    var cityNames: Set<String> {
        return Set(areas.map { $0.name })
    }

    func cityAt(latitude: Double, longitude: Double) -> String? {
        if latitude.isNaN || longitude.isNaN
            || latitude.isInfinite || longitude.isInfinite
            || latitude < -90.0 || latitude > 90.0
            || longitude < -180.0 || longitude > 180.0 {
            return nil
        }
        return areas.first { area in
            area.polygons.contains { $0.contains(x: longitude * 10000, y: latitude * 10000) }
        }?.name
    }

    // MARK: - SCB1 解析

    enum ParseError: Error, LocalizedError {
        case unsupportedFormat
        case invalidCount
        case unexpectedEndOfStream
        case missingName
        case tooLarge
        case invalidCoordinate
        case trailingData
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported city boundary format"
            case .invalidCount: return "Invalid city boundary count"
            // 对齐 Android DataInputStream EOFException: 截断流报"流提前结束", 不冒充计数错误
            case .unexpectedEndOfStream: return "Unexpected end of city boundary stream"
            case .missingName: return "Missing city name"
            case .tooLarge: return "City boundary data too large"
            case .invalidCoordinate: return "Invalid city boundary coordinate"
            case .trailingData: return "Trailing city boundary data"
            case .cancelled: return "cancelled"
            }
        }
    }

    /// SCB1 流式解析 — 不建 JSON 树、不建点对象, 直接读进缩放整数 ring。
    /// 调用方持有流。每 ring 与每 256 点检查一次取消。
    /// `checkCancelled` 可抛错中断扫描(Android `{ coroutineContext.ensureActive() }` 语义):
    /// 抛 `CancellationError` 归一为 `ParseError.cancelled`, 其余错误原样传播。
    static func parse(_ stream: InputStream, checkCancelled: () throws -> Void = {}) throws -> OfflineSchoolCityIndex {
        let input = stream
        input.open()
        defer { input.close() }
        func checkCancellation() throws {
            do { try checkCancelled() }
            catch is CancellationError { throw ParseError.cancelled }
        }
        try checkCancellation()

        var buffer = [UInt8](repeating: 0, count: 4)

        func readInt32() throws -> Int32 {
            var read = 0
            while read < 4 {
                let n = input.read(&buffer, maxLength: 4 - read)
                // 对齐 Android DataInputStream.readInt 的 EOFException: 提前结束 = 流截断
                if n <= 0 { throw ParseError.unexpectedEndOfStream }
                read += n
            }
            // 大端 (Java DataInputStream.writeInt 语义)
            let v = (Int32(buffer[0]) << 24) | (Int32(buffer[1]) << 16)
                | (Int32(buffer[2]) << 8) | Int32(buffer[3])
            return v
        }

        func count(minimum: Int32, maximum: Int32) throws -> Int {
            let v = try readInt32()
            guard v >= minimum && v <= maximum else { throw ParseError.invalidCount }
            return Int(v)
        }

        guard try readInt32() == 0x53434231 else { throw ParseError.unsupportedFormat }

        var totalPoints = 0
        var areas: [Area] = []
        let areaCount = try count(minimum: 1, maximum: 10000)
        for _ in 0..<areaCount {
            try checkCancellation()
            let nameLen = try count(minimum: 1, maximum: 256)
            var nameBytes = [UInt8](repeating: 0, count: nameLen)
            var read = 0
            while read < nameLen {
                let n = input.read(&nameBytes, maxLength: nameLen - read)
                if n <= 0 { throw ParseError.unexpectedEndOfStream }
                read += n
            }
            // Java `toString(Charsets.UTF_8)` 对非法字节序列用 U+FFFD 替换(名字仍非空白);
            // String(decoding:as:) 与之等价 — 不能用 String(bytes:encoding:) 的 nil→"" 路径。
            let name = String(decoding: nameBytes, as: UTF8.self)
            guard !name.isBlank else { throw ParseError.missingName }
            var polygons: [Polygon] = []
            let polygonCount = try count(minimum: 1, maximum: 10000)
            for _ in 0..<polygonCount {
                var rings: [Ring] = []
                let ringCount = try count(minimum: 1, maximum: 10000)
                for _ in 0..<ringCount {
                    try checkCancellation()
                    let points = try count(minimum: 3, maximum: 1_000_000)
                    totalPoints += points
                    guard totalPoints <= 2_000_000 else { throw ParseError.tooLarge }
                    var coordinates = [Int32](repeating: 0, count: points * 2)
                    for point in 0..<points {
                        if point % 256 == 0 { try checkCancellation() }
                        let longitude = try readInt32()
                        let latitude = try readInt32()
                        guard longitude >= -1_800_000 && longitude <= 1_800_000
                            && latitude >= -900_000 && latitude <= 900_000 else {
                            throw ParseError.invalidCoordinate
                        }
                        coordinates[point * 2] = longitude
                        coordinates[point * 2 + 1] = latitude
                    }
                    rings.append(Ring(coordinates: coordinates))
                }
                polygons.append(Polygon(rings: rings))
            }
            areas.append(Area(name: name, polygons: polygons))
        }
        // EOF 后不得有尾随字节 — 对齐 Android `require(input.read() == -1)`:
        // Foundation InputStream(data:) 在流末尾返回 0(实测非 -1), 必须按 hasBytesAvailable
        // 判"有无尾随字节", 直接把 0 当尾随数据会让每个合法流都误报 .trailingData。
        var probe: UInt8 = 0
        if input.hasBytesAvailable {
            let n = input.read(&probe, maxLength: 1)
            if n > 0 { throw ParseError.trailingData }
            if n < 0 { throw ParseError.unexpectedEndOfStream }
        }
        try checkCancellation()
        return OfflineSchoolCityIndex(areas: areas)
    }
}
