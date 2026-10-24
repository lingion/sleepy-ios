// OfflineSchoolCityIndexTests.swift — ← OfflineSchoolCityIndexTest.kt (8 用例逐条)
// + SchoolBoundaryFixture.kt 的 SCB1 字节构造器镜像(hole/island fixture)。
//
// 真资产 school_city_boundaries.bin.gz 打进 app bundle(Sleepy/resources),
// 测试经 Bundle(for: JwImportViewModel.self) 取 — 与 JwJsonParserTests 取
// schools.json 的先例一致; .bin 兜底对齐 Android AAPT 去 .gz 后缀的行为。
//
// 资源缺失 ≠ 失败: 与 Android offlineIndex() catch→null 的生产语义一致,
// 真资产用例在资源不可得时 XCTSkip(单元测试不逼 xcodegen 打包布局就位)。

import XCTest
import Compression
@testable import Sleepy

final class OfflineSchoolCityIndexTests: XCTestCase {

    // MARK: - 真资产加载

    /// gunzip: 剥 RFC 1952 容器 → raw inflate。SchoolCityLocator 内私有 gunzipped() 不可复用,
    /// 测试自带同语义实现(FEXTRA/FNAME/FCOMMENT/FHCRC + ISIZE 缓冲)。
    private static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b else { return nil }
        var offset = 10
        let flags = data[data.startIndex + 3]
        func bounds(_ n: Int) -> Bool { offset + n <= data.count }
        if flags & 0x04 != 0 { // FEXTRA
            guard bounds(2) else { return nil }
            let xlen = Int(data[data.startIndex + offset]) | (Int(data[data.startIndex + offset + 1]) << 8)
            offset += 2 + xlen
        }
        for bit: UInt8 in [0x08, 0x10] where flags & bit != 0 { // FNAME / FCOMMENT
            while offset < data.count && data[data.startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset + 8 <= data.count else { return nil }
        let t = data.count - 4
        let isizeLE = UInt32(data[t]) | (UInt32(data[t + 1]) << 8)
            | (UInt32(data[t + 2]) << 16) | (UInt32(data[t + 3]) << 24)
        let outSize = Int(isizeLE) &+ 65_536
        let src = Array(data[(data.startIndex + offset)..<(data.endIndex - 8)])
        var out = [UInt8](repeating: 0, count: outSize)
        let n = src.withUnsafeBytes { sp in
            out.withUnsafeMutableBytes { dp in
                compression_decode_buffer(
                    dp.bindMemory(to: UInt8.self).baseAddress!, outSize,
                    sp.bindMemory(to: UInt8.self).baseAddress!, src.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        return Data(out[0..<n])
    }

    /// 生产入口的镜像: .bin.gz 优先、.bin 兜底 → gunzip → SCB1 流式解析。
    private static func loadRealIndex() throws -> OfflineSchoolCityIndex {
        let bundle = Bundle(for: OfflineSchoolCityIndexTests.self)
        let appBundle = Bundle(for: JwImportViewModel.self) // @testable → app 类型定位 app bundle
        func asset(_ ext: String) -> Data? {
            guard let url = appBundle.url(forResource: "school_city_boundaries", withExtension: ext)
                ?? bundle.url(forResource: "school_city_boundaries", withExtension: ext)
                ?? Bundle.main.url(forResource: "school_city_boundaries", withExtension: ext)
            else { return nil }
            return try? Data(contentsOf: url)
        }
        guard let raw = asset("gz") ?? asset("bin") else {
            throw XCTSkip("school_city_boundaries 资产未打进测试可见的 bundle")
        }
        let decompressed = (raw.count > 1 && raw[0] == 0x1f && raw[1] == 0x8b) ? (gunzip(raw) ?? raw) : raw
        return try OfflineSchoolCityIndex.parse(InputStream(data: decompressed))
    }

    /// school_cities.json 文本(同城断言两个用例共用)。
    private static func loadSchoolCitiesText() throws -> String {
        let appBundle = Bundle(for: JwImportViewModel.self)
        let bundle = Bundle(for: OfflineSchoolCityIndexTests.self)
        guard let url = appBundle.url(forResource: "school_cities", withExtension: "json")
            ?? bundle.url(forResource: "school_cities", withExtension: "json")
            ?? Bundle.main.url(forResource: "school_cities", withExtension: "json")
        else { throw XCTSkip("school_cities.json 未打进测试可见的 bundle") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - ← SchoolBoundaryFixture.kt (SCB1 字节构造器, JSON [lon, lat] 度数)

    private func fixtureBytes(_ areas: [[String: Any]]) -> Data {
        func be(_ v: Int32, into d: inout Data) {
            d.append(UInt8(truncatingIfNeeded: v >> 24)); d.append(UInt8(truncatingIfNeeded: v >> 16))
            d.append(UInt8(truncatingIfNeeded: v >> 8)); d.append(UInt8(truncatingIfNeeded: v))
        }
        var out = Data()
        be(0x53434231, into: &out)
        be(Int32(areas.count), into: &out)
        for area in areas {
            let name = Array((area["name"] as! String).utf8)
            be(Int32(name.count), into: &out)
            out.append(contentsOf: name)
            // polygons: polygon([[Double] ring]) → ring([[Double] point]) → point([lon, lat])
            let polygons = area["polygons"] as! [[[[Double]]]]
            be(Int32(polygons.count), into: &out)
            for polygon in polygons {
                be(Int32(polygon.count), into: &out)
                for ring in polygon {
                    be(Int32(ring.count), into: &out)
                    for coordinates in ring {
                        be(Int32((coordinates[0] * 10000).rounded()), into: &out)
                        be(Int32((coordinates[1] * 10000).rounded()), into: &out)
                    }
                }
            }
        }
        return out
    }

    private func areaJSON(name: String, polygons: [[[[Double]]]]) -> [String: Any] {
        ["name": name, "polygons": polygons]
    }

    private func parseFixture(_ areas: [[String: Any]]) throws -> OfflineSchoolCityIndex {
        try OfflineSchoolCityIndex.parse(InputStream(data: fixtureBytes(areas)))
    }

    // MARK: - 用例 1: Huizhou coordinate resolves without any geocoder

    func testHuizhouCoordinateResolvesWithoutGeocoder() throws {
        let index = try Self.loadRealIndex()
        XCTAssertEqual("惠州市", index.cityAt(latitude: 23.103775, longitude: 114.471620))
    }

    // MARK: - 用例 2: adjacent Guangdong cities do not use the nearest city centre

    func testAdjacentGuangdongCitiesDoNotUseNearestCentre() throws {
        let index = try Self.loadRealIndex()
        XCTAssertEqual("佛山市", index.cityAt(latitude: 23.1385, longitude: 113.0270))
        XCTAssertEqual("广州市", index.cityAt(latitude: 23.1291, longitude: 113.2644))
        XCTAssertEqual("深圳市", index.cityAt(latitude: 22.5431, longitude: 114.0579))
        XCTAssertEqual("东莞市", index.cityAt(latitude: 23.0207, longitude: 113.7518))
    }

    // MARK: - 用例 3: municipality districts resolve to city names used in school data

    func testMunicipalitiesResolveToSchoolDataNames() throws {
        let index = try Self.loadRealIndex()
        XCTAssertEqual("北京市", index.cityAt(latitude: 39.9042, longitude: 116.4074))
        XCTAssertEqual("上海市", index.cityAt(latitude: 31.2304, longitude: 121.4737))
        XCTAssertEqual("天津市", index.cityAt(latitude: 39.1256, longitude: 117.1902))
        XCTAssertEqual("重庆市", index.cityAt(latitude: 29.5630, longitude: 106.5516))
    }

    // MARK: - 用例 4: locations outside boundaries never return an arbitrary Chinese city

    func testOutsideBoundariesReturnsNil() throws {
        let index = try Self.loadRealIndex()
        XCTAssertNil(index.cityAt(latitude: 37.4220, longitude: -122.0840))
        XCTAssertNil(index.cityAt(latitude: 0.0, longitude: 0.0))
        XCTAssertNil(index.cityAt(latitude: 35.6762, longitude: 139.6503))
    }

    // MARK: - 用例 5: invalid coordinates cannot resolve to a city

    func testInvalidCoordinatesCannotResolve() throws {
        let index = try Self.loadRealIndex()
        XCTAssertNil(index.cityAt(latitude: Double.nan, longitude: 114.0))
        XCTAssertNil(index.cityAt(latitude: 23.0, longitude: Double.infinity))
        XCTAssertNil(index.cityAt(latitude: 91.0, longitude: 114.0))
        XCTAssertNil(index.cityAt(latitude: 23.0, longitude: -181.0))
    }

    // MARK: - 用例 6: holes and disconnected islands are respected

    func testHolesAndIslandsAreRespected() throws {
        let small = try parseFixture([[
            "name": "A",
            "polygons": [
                [
                    [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                    [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
                ],
                [
                    [[20, 20], [22, 20], [22, 22], [20, 22], [20, 20]],
                ],
            ] as [[[[Double]]]],
        ]])
        XCTAssertEqual("A", small.cityAt(latitude: 1.0, longitude: 1.0))
        XCTAssertNil(small.cityAt(latitude: 5.0, longitude: 5.0))          // hole
        XCTAssertEqual("A", small.cityAt(latitude: 21.0, longitude: 21.0)) // island
        XCTAssertNil(small.cityAt(latitude: 15.0, longitude: 15.0))        // 两块之间
        XCTAssertEqual("A", small.cityAt(latitude: 0.0, longitude: 2.0))   // 边界上算包含
    }

    // MARK: - 用例 7: Huizhou city result selects its actual school entry

    func testHuizhouSelectsActualSchoolEntry() throws {
        let index = try Self.loadRealIndex()
        let school = JwSchoolInfo(sortKey: "H", name: "惠州学院", cities: ["惠州市"])
        let other = JwSchoolInfo(sortKey: "G", name: "广东东软学院", cities: ["佛山市"])
        let city = try XCTUnwrap(index.cityAt(latitude: 23.103775, longitude: 114.471620))
        XCTAssertEqual([school], SchoolCityIndex.schoolsInCity([school, other], city: city))
    }

    // MARK: - 用例 8: all configured school cities exist in the bundled boundary names

    func testAllConfiguredSchoolCitiesHaveBoundaries() throws {
        let index = try Self.loadRealIndex()
        let names = index.cityNames
        let cities = try SchoolCityIndex.parse(Self.loadSchoolCitiesText())
        for (school, locations) in cities {
            for city in locations {
                XCTAssertTrue(names.contains(city), "Missing boundary for \(school): \(city)")
            }
        }
    }

    // MARK: - 用例 9 (fixture 版补充, 覆盖真资产用例 8 的资源依赖之外):
    // 取消钩子 — CancellationError 归一为 .cancelled (Android ensureActive 语义)

    func testCancellationHookMapsToCancelledError() throws {
        let bytes = fixtureBytes([areaJSON(name: "A", polygons: [[
            [[0, 0], [10, 0], [10, 10], [0, 10]],
        ]])])
        var calls = 0
        XCTAssertThrowsError(try OfflineSchoolCityIndex.parse(InputStream(data: bytes)) {
            calls += 1
            if calls == 2 { throw CancellationError() }
        }) { error in
            XCTAssertEqual(error as? OfflineSchoolCityIndex.ParseError, .cancelled)
        }
        XCTAssertGreaterThan(calls, 1, "钩子应在解析循环内被反复调用, 不是一次性前置检查")
        // 其它错误原样传播, 不被归一吞掉
        struct Boom: Error {}
        XCTAssertThrowsError(try OfflineSchoolCityIndex.parse(InputStream(data: bytes)) {
            throw Boom()
        })
    }

    // MARK: - 截断流 / 尾随字节 / 非法 UTF-8 名字 (对齐 Android EOFException / U+FFFD 语义)

    func testTruncatedStreamReportsEndOfStream() throws {
        let bytes = fixtureBytes([areaJSON(name: "A", polygons: [[
            [[0, 0], [10, 0], [10, 10]],
        ]])])
        XCTAssertThrowsError(try OfflineSchoolCityIndex.parse(InputStream(data: bytes.prefix(9)))) { error in
            XCTAssertEqual(error as? OfflineSchoolCityIndex.ParseError, .unexpectedEndOfStream)
        }
        // 完整流不得误报尾随数据 (旧实现 read 返回 0 被当尾随 → 每个合法流都炸)
        XCTAssertNoThrow(try OfflineSchoolCityIndex.parse(InputStream(data: bytes)))
        var withTrailer = bytes
        withTrailer.append(0x00)
        XCTAssertThrowsError(try OfflineSchoolCityIndex.parse(InputStream(data: withTrailer))) { error in
            XCTAssertEqual(error as? OfflineSchoolCityIndex.ParseError, .trailingData)
        }
    }

    func testInvalidUtf8NameUsesReplacementChar() throws {
        // name bytes "A\xFFB" — Java toString(UTF_8) → "A\u{FFFD}B"; 不应报 missingName
        var out = Data()
        func be(_ v: Int32) {
            out.append(UInt8(truncatingIfNeeded: v >> 24)); out.append(UInt8(truncatingIfNeeded: v >> 16))
            out.append(UInt8(truncatingIfNeeded: v >> 8)); out.append(UInt8(truncatingIfNeeded: v))
        }
        be(0x53434231); be(1); be(3)
        out.append(contentsOf: [0x41, 0xFF, 0x42] as [UInt8])
        be(1); be(1); be(3)
        for (x, y) in [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)] { be(Int32(x * 10000)); be(Int32(y * 10000)) }
        let parsed = try OfflineSchoolCityIndex.parse(InputStream(data: out))
        XCTAssertEqual(["A\u{FFFD}B"], Array(parsed.cityNames))
    }

    // MARK: - moved-school (29.2,115.8)→"九江市" not "南昌市" — 真资产不可得时跳过

    func testMovedSchoolResolvesByLocationNotName() throws {
        let index = try Self.loadRealIndex()
        let cities = try SchoolCityIndex.parse(Self.loadSchoolCitiesText())
        let moved = JwSchoolInfo(sortKey: "J", name: "江西农业大学南昌商学院",
                                cities: cities["江西农业大学南昌商学院"] ?? ["九江市"])
        let city = try XCTUnwrap(index.cityAt(latitude: 29.2, longitude: 115.8)) // 共青城一带
        XCTAssertEqual("九江市", city)
        XCTAssertEqual([moved], SchoolCityIndex.schoolsInCity([moved], city: city))
        XCTAssertTrue(SchoolCityIndex.schoolsInCity([moved], city: "南昌市").isEmpty)
    }
}
