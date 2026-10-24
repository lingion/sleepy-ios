// SchoolLocationPolicyTests.swift — ← data/jw/SchoolLocationPolicyTest.kt (v1.0.61)
//
// 八个用例逐一对应 Android 侧 SchoolLocationPolicyTest:
//   1. 权限组合 → precise / approximate / nil
//   2. approximate 排除 "gps"(含早前 fine 授权场景) + distinct 保序
//   3. 年龄边界 30s 可用 / 31s / -1s / 300s 拒绝(双模式)
//   4. 精度边界 precise 1000/1001, approximate 10000/10001, 0/-1/NaN/+Inf 拒绝
//   5. 非法坐标 NaN/91/-181/+Inf 拒绝
//   6. forCityLookup 舍入(23.123456→23.12, 114.456789→114.46, +800m, ageNanos 保留,
//      precise 原样返回) — 含 Kotlin round=向+∞破 .5 平局的负坐标对齐断言
//   7. 边界歧义: 500m 跨界样本拒绝, 10m 精确样本命中 "A"
//   8. approximate 舍入落到边界附近不得制造"自信城市"
//
// 边界 fixture 镜像 SchoolBoundaryFixture.kt: JSON 可读源 → SCB1 大端字节流 →
// OfflineSchoolCityIndex.parse。历史依赖(已消除): OfflineSchoolCityIndex 的 EOF
// 探针曾把 InputStream(data:) 末尾 read 返回的 0 当尾随数据, 有效流也抛
// .trailingData; F039 已改为按 hasBytesAvailable 判尾随字节(0-at-EOF 合法),
// 用例 7/8 与 boundaryIndex 不再受该依赖阻塞。

import XCTest
@testable import Sleepy

final class SchoolLocationPolicyTests: XCTestCase {

    // MARK: - fixtures(镜像 Android 测试助手)

    private func makeFix(accuracy: Double = 30.0, ageSeconds: Int64 = 1,
                         latitude: Double = 23.123456, longitude: Double = 114.456789) -> SchoolLocationFix {
        SchoolLocationFix(latitude: latitude, longitude: longitude,
                          accuracyMeters: accuracy, ageNanos: ageSeconds * 1_000_000_000)
    }

    /// 两格相邻城市 A:[0,1]×[0,1], B:[1,2]×[0,1](与 Kotlin border fixture 一致)。
    private static let borderJSON = """
    {"areas":[
        {"name":"A","polygons":[[[[0,0],[1,0],[1,1],[0,1],[0,0]]]]},
        {"name":"B","polygons":[[[[1,0],[2,0],[2,1],[1,1],[1,0]]]]}
    ]}
    """

    /// SchoolBoundaryFixture.kt 的 iOS 对应物: 可读 JSON → SCB1 字节流 → parse。
    /// 结构: areas[] → polygons[] → rings[] → points[](每点 [longitude, latitude], 度×10000)。
    private func boundaryIndex(json: String) throws -> OfflineSchoolCityIndex {
        let data = try XCTUnwrap(json.data(using: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let areas = try XCTUnwrap(root["areas"] as? [[String: Any]])

        var out = Data()
        func appendInt32(_ v: Int32) {
            var big = v.bigEndian
            withUnsafeBytes(of: &big) { out.append(contentsOf: $0) }
        }
        appendInt32(0x53434231) // "SCB1"
        appendInt32(Int32(areas.count))
        for area in areas {
            let name = try XCTUnwrap((area["name"] as? String)?.data(using: .utf8))
            appendInt32(Int32(name.count))
            out.append(name)
            let polys = try XCTUnwrap(area["polygons"] as? [[Any]])
            appendInt32(Int32(polys.count))
            for polygon in polys {
                let rings = try XCTUnwrap(polygon as? [[Any]])
                appendInt32(Int32(rings.count))
                for ring in rings {
                    let points = try XCTUnwrap(ring as? [[Any]])
                    appendInt32(Int32(points.count))
                    for point in points {
                        let lon = try XCTUnwrap((point[0] as? NSNumber)?.doubleValue)
                        let lat = try XCTUnwrap((point[1] as? NSNumber)?.doubleValue)
                        appendInt32(Int32((lon * 10000).rounded()))
                        appendInt32(Int32((lat * 10000).rounded()))
                    }
                }
            }
        }
        return try OfflineSchoolCityIndex.parse(InputStream(data: out))
    }

    // MARK: - 用例 1: 权限矩阵

    func testSystemGrantsSelectPreciseApproximateOrNoLocation() {
        XCTAssertEqual(SchoolLocationPolicy.modeForPermissions(coarse: true, fine: true), .precise)
        XCTAssertEqual(SchoolLocationPolicy.modeForPermissions(coarse: true, fine: false), .approximate)
        XCTAssertNil(SchoolLocationPolicy.modeForPermissions(coarse: false, fine: false))
        XCTAssertNil(SchoolLocationPolicy.modeForPermissions(coarse: false, fine: true))
    }

    // MARK: - 用例 2: provider 过滤

    func testApproximateExcludesGPSEvenWithAnEarlierPreciseGrant() {
        let providers = ["gps", "network", "fused", "passive", "network"]
        XCTAssertEqual(SchoolLocationPolicy.providers(mode: .approximate, available: providers),
                       ["network", "fused"])
        XCTAssertEqual(SchoolLocationPolicy.providers(mode: .precise, available: providers),
                       ["gps", "network", "fused"])
    }

    // MARK: - 用例 3: 年龄边界

    func testOnlySamplesNoOlderThanThirtySecondsCanBeFastResults() {
        for mode in [SchoolLocationMode.precise, .approximate] {
            XCTAssertTrue(SchoolLocationPolicy.usable(mode: mode, fix: makeFix(ageSeconds: 30)))
            XCTAssertFalse(SchoolLocationPolicy.usable(mode: mode, fix: makeFix(ageSeconds: 31)))
            XCTAssertFalse(SchoolLocationPolicy.usable(mode: mode, fix: makeFix(ageSeconds: -1)))
            XCTAssertFalse(SchoolLocationPolicy.usable(mode: mode, fix: makeFix(ageSeconds: 300)))
        }
    }

    // MARK: - 用例 4: 精度边界

    func testAFastNetworkResponseMustMeetTheSelectedAccuracy() {
        XCTAssertTrue(SchoolLocationPolicy.usable(mode: .precise, fix: makeFix(accuracy: 1_000.0)))
        XCTAssertFalse(SchoolLocationPolicy.usable(mode: .precise, fix: makeFix(accuracy: 1_001.0)))
        XCTAssertTrue(SchoolLocationPolicy.usable(mode: .approximate, fix: makeFix(accuracy: 10_000.0)))
        XCTAssertFalse(SchoolLocationPolicy.usable(mode: .approximate, fix: makeFix(accuracy: 10_001.0)))
        for accuracy in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertFalse(SchoolLocationPolicy.usable(mode: .approximate, fix: makeFix(accuracy: accuracy)))
        }
    }

    // MARK: - 用例 5: 非法坐标

    func testInvalidCoordinatesCannotBecomeFastResults() {
        let base = makeFix()
        let samples = [
            SchoolLocationFix(latitude: Double.nan, longitude: base.longitude,
                              accuracyMeters: base.accuracyMeters, ageNanos: base.ageNanos),
            SchoolLocationFix(latitude: 91.0, longitude: base.longitude,
                              accuracyMeters: base.accuracyMeters, ageNanos: base.ageNanos),
            SchoolLocationFix(latitude: base.latitude, longitude: -181.0,
                              accuracyMeters: base.accuracyMeters, ageNanos: base.ageNanos),
            SchoolLocationFix(latitude: base.latitude, longitude: Double.infinity,
                              accuracyMeters: base.accuracyMeters, ageNanos: base.ageNanos),
        ]
        for sample in samples {
            XCTAssertFalse(SchoolLocationPolicy.usable(mode: .approximate, fix: sample))
        }
    }

    // MARK: - 用例 6: forCityLookup 舍入 + 平局语义

    func testApproximateRoundsAndAccountsForAddedUncertainty() {
        let source = makeFix()
        let coarse = SchoolLocationPolicy.forCityLookup(mode: .approximate, fix: source)
        XCTAssertEqual(coarse.latitude, 23.12, accuracy: 0.0)
        XCTAssertEqual(coarse.longitude, 114.46, accuracy: 0.0)
        XCTAssertEqual(coarse.accuracyMeters, 830.0, accuracy: 0.0)
        XCTAssertEqual(coarse.ageNanos, source.ageNanos)
        XCTAssertEqual(SchoolLocationPolicy.forCityLookup(mode: .precise, fix: source), source)
    }

    /// Kotlin round(x) = floor(x+0.5)(向 +∞ 破 .5 平局), 负坐标平局与 Swift 默认
    /// .rounded()(远离零)差 1: -23.125×100 = -2312.5 → Kotlin floor(-2312.0) = -2312
    /// → -23.12, 旧 Swift 远离零 → -2313 → -23.13。经核对 double 语义:
    /// -114.455×100 正确舍入为 -11445.5(积距 11445.5 仅 ~1.7e-13 < 半 ulp 9.09e-13),
    /// floor(-11445.5+0.5) = -11445 → -114.45(旧 Swift 会给 -114.46)。
    /// 中国坐标恒正无实害, 但锁死语义防南/西半球漂移。
    func testRoundingMatchesKotlinFloorTiesOnNegativeHalf() {
        let fix = SchoolLocationFix(latitude: -23.125, longitude: -114.455,
                                    accuracyMeters: 30.0, ageNanos: 1_000_000_000)
        let coarse = SchoolLocationPolicy.forCityLookup(mode: .approximate, fix: fix)
        XCTAssertEqual(coarse.latitude, -23.12, accuracy: 1e-9)
        XCTAssertEqual(coarse.longitude, -114.45, accuracy: 1e-9)
    }

    // MARK: - 用例 7: 边界歧义拒绝

    func testWideUncertaintyCrossingCityBorderIsRejectedWhilePreciseFixResolves() throws {
        let border = try boundaryIndex(json: Self.borderJSON)
        let sample = SchoolLocationFix(latitude: 0.5, longitude: 0.999,
                                       accuracyMeters: 500.0, ageNanos: 0)
        XCTAssertNil(SchoolLocationPolicy.city(index: border, fix: sample))
        XCTAssertEqual(SchoolLocationPolicy.city(index: border, fix:
            SchoolLocationFix(latitude: 0.5, longitude: 0.999, accuracyMeters: 10.0, ageNanos: 0)), "A")
    }

    // MARK: - 用例 8: 舍入近界不制造自信城市

    func testApproximateRoundingNearABorderDoesNotManufactureAConfidentCity() throws {
        let border = try boundaryIndex(json: Self.borderJSON)
        let sample = SchoolLocationFix(latitude: 0.5, longitude: 0.999,
                                       accuracyMeters: 10.0, ageNanos: 0)
        XCTAssertNil(SchoolLocationPolicy.city(index: border,
            fix: SchoolLocationPolicy.forCityLookup(mode: .approximate, fix: sample)))
        XCTAssertEqual(SchoolLocationPolicy.city(index: border, fix:
            SchoolLocationFix(latitude: 0.5, longitude: 0.5, accuracyMeters: 5_000.0, ageNanos: 0)), "A")
        XCTAssertNil(SchoolLocationPolicy.city(index: border, fix:
            SchoolLocationFix(latitude: 20.0, longitude: 20.0, accuracyMeters: 10.0, ageNanos: 0)))
    }
}
