// CourseColorHarmonyTests.swift — ← util/CourseColorHarmonyTest.kt 逐用例移植 (v1.0.62, GPL-3.0)
//
// 课程配色和谐化契约(spec docs/spec-course-color-harmony-2026-10-18.md §6 测试 1/2/3′)。
// 锁的不变量:
//   1. 禁区不变量 — 对任意 anchor × 任意 groupId, safeArcHue / resolveHueWithSpacing
//      产出与 anchor 的环上距恒在 (30°,150°)∪(210°,330°) 允许弧内;
//      违反 = 用户肉眼可见的「紫配黄扎眼」或「课色与 UI 主色混淆」回归。
//   2. 确定性 — 同输入重复计算逐位相等(落库值/兜底值同源的前提)。
//   3. 间距保证 — 增量避让后 13 门课两两环距 ≥ 10°(红绿验证: MIN_SEP 传 90° 必须挂满)。
//   4. 钉死性 — 已有课 hue 不因新课加入而改变(taken 只增不改的语义前提)。
//   5. 饱和退化 — 超过弧容量(>24门)不抛异常、仍在允许弧。
//
// 平台差异: 原版本 用 java.util.UUID.nameUUIDFromBytes 生成确定性 groupId;
// iOS 用同语义的确定性 UUIDv3(MD5, RFC 4122 §4.3)自实现 — 见 deterministicUUIDv3。

import XCTest
import CommonCrypto
import SwiftUI
@testable import Sleepy

final class CourseColorHarmonyTests: XCTestCase {

    // MARK: - 几何助手(与 原 CourseColorHarmonyTest 同一定义)

    private func ringDelta(_ a: Float, _ b: Float) -> Float {
        let d = ((a - b).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private func zoneDist(_ hue: Float, _ anchor: Float) -> Float {
        ((hue - anchor).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private func assertInAllowedArc(_ hue: Float, _ anchor: Float,
                                    _ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        // spec §2.2 允许带为半开 [30,150)∪[210,330)(+30° 边界本身已可辨,归允许带)
        let dist = zoneDist(hue, anchor)
        let inAllowedA = dist >= 30 && dist < 150
        let inAllowedB = dist >= 210 && dist < 330
        XCTAssertTrue(inAllowedA || inAllowedB,
                      "\(ctx) hue=\(hue) anchor=\(anchor) dist=\(dist) 落入禁区",
                      file: file, line: line)
    }

    /// 确定性 UUIDv3(MD5, RFC 4122 §4.3) — 等价 原版本 UUID.nameUUIDFromBytes
    /// (nameUUIDFromBytes = MD5(namespaceBytes + name) 取 16 字节、置 version/variant 位)。
    /// 确定性是本测试唯一要求; 逐字节对齐非必需。
    private func deterministicUUIDv3(_ name: String) -> String {
        let namespace = Array("sleepy-course-color-harmony-ns".utf8)
        let nameBytes = Array(name.utf8)
        var input = namespace
        input.append(contentsOf: nameBytes)
        var digest = [UInt8](repeating: 0, count: 16)
        digest.withUnsafeMutableBytes { raw in
            let ok = CC_MD5(input, 16, raw.baseAddress!)
            _ = ok
        }
        digest[6] = (digest[6] & 0x0F) | 0x30  // version 3
        digest[8] = (digest[8] & 0x3F) | 0x80  // RFC 4122 variant
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let p = Array(hex)
        return "\(String(p[0..<8]))-\(String(p[8..<12]))-\(String(p[12..<16]))-\(String(p[16..<20]))-\(String(p[20..<32]))"
    }

    private lazy var groupIds: [String] = (1...200).map { i in
        deterministicUUIDv3("course-\(i)")
    }

    // ───────── 不变量 1: 禁区 ─────────

    func testSafeArcHueNeverFallsIntoForbiddenZones() {
        var anchor: Float = 0
        while anchor < 360 {
            for gid in groupIds {
                let hue = CourseColorUtil.safeArcHue(anchor, gid)
                assertInAllowedArc(hue, anchor, "safeArcHue gid=\(gid)")
            }
            anchor += 15
        }
    }

    func testResolveHueNeverFallsIntoForbiddenZonesEvenWithTakenCrowding() {
        // 30 门课顺序 assign(超弧容量触发 fallback),全程每个产出必须在允许弧
        let anchor: Float = 264
        var taken: [Float] = []
        for gid in groupIds.prefix(30) {
            let hue = CourseColorUtil.resolveHueWithSpacing(anchor, gid, taken)
            assertInAllowedArc(hue, anchor, "resolve gid=\(gid)")
            taken.append(hue)
        }
    }

    // ───────── 不变量 2: 确定性 ─────────

    func testSafeArcHueIsDeterministic() {
        for gid in groupIds.prefix(50) {
            XCTAssertEqual(CourseColorUtil.safeArcHue(264, gid),
                           CourseColorUtil.safeArcHue(264, gid), accuracy: 0)
        }
    }

    func testResolveHueIsDeterministic() {
        let taken = groupIds.prefix(5).map { CourseColorUtil.safeArcHue(120, $0) }
        for _ in 0..<3 {
            XCTAssertEqual(CourseColorUtil.resolveHueWithSpacing(120, groupIds[42], taken),
                           CourseColorUtil.resolveHueWithSpacing(120, groupIds[42], taken),
                           accuracy: 0)
        }
    }

    func testSafeArcHueOutputRangeIsAlwaysNormalized() {
        for anchor: Float in [0, 90, 180, 270, 350] {
            for gid in groupIds {
                let hue = CourseColorUtil.safeArcHue(anchor, gid)
                XCTAssertTrue(hue >= 0 && hue < 360, "hue=\(hue) 越界")
            }
        }
    }

    // ───────── 不变量 3: 间距 ─────────

    func testIncrementalAssign13CoursesKeepMinimumSeparation() {
        let anchor: Float = 264
        var assigned: [Float] = []
        for gid in groupIds.prefix(13) {
            assigned.append(CourseColorUtil.resolveHueWithSpacing(anchor, gid, assigned))
        }
        for i in assigned.indices {
            for j in (i + 1)..<assigned.count {
                XCTAssertTrue(ringDelta(assigned[i], assigned[j]) >= 10,
                              "第 \(i)/\(j) 门课 hue 间距不足: \(assigned[i]) vs \(assigned[j])")
            }
        }
    }

    func testEmptyAnchorAlsoSeparates() {
        // 第二 anchor 交叉验证间距不变量不靠运气
        let anchor: Float = 45
        var assigned: [Float] = []
        for gid in groupIds.prefix(13) {
            assigned.append(CourseColorUtil.resolveHueWithSpacing(anchor, gid, assigned))
        }
        for i in assigned.indices {
            for j in (i + 1)..<assigned.count {
                XCTAssertTrue(ringDelta(assigned[i], assigned[j]) >= 10)
            }
        }
    }

    func testSpacingAssertionIsNotVacuousMinSep90MustFailToHold() {
        // 红绿验证: 240° 弧容不下 13 门课两两 ≥90°(每弧至多 2 点),
        // 若此测试反而「间距全 ≥90」= 上面的 10° 断言根本没在约束什么。
        let anchor: Float = 264
        var assigned: [Float] = []
        for gid in groupIds.prefix(13) {
            assigned.append(CourseColorUtil.resolveHueWithSpacing(anchor, gid, assigned, minSep: 90))
        }
        let anyViolating = assigned.indices.contains { i in
            ((i + 1)..<assigned.count).contains { j in ringDelta(assigned[i], assigned[j]) < 90 }
        }
        XCTAssertTrue(anyViolating, "minSep=90° 下必存在违反对(否则 10° 断言是空断言)")
    }

    // ───────── 不变量 4: 钉死性 ─────────

    func testExistingHuesArePinnedWhenNewCourseJoins() {
        let anchor: Float = 264
        var first10: [Float] = []
        for gid in groupIds.prefix(10) {
            first10.append(CourseColorUtil.resolveHueWithSpacing(anchor, gid, first10))
        }
        var with11 = first10
        with11.append(CourseColorUtil.resolveHueWithSpacing(anchor, groupIds[10], with11))
        // 前 10 门课 hue 一位不变
        for i in 0..<10 {
            XCTAssertEqual(first10[i], with11[i], accuracy: 0)
        }
    }

    // ───────── 不变量 5: 饱和退化安全 ─────────

    func testOverSaturatedArcDoesNotThrowAndStaysInArc() {
        let anchor: Float = 180
        var taken: [Float] = []
        for gid in groupIds.prefix(40) {
            let hue = CourseColorUtil.resolveHueWithSpacing(anchor, gid, taken)
            assertInAllowedArc(hue, anchor, "over-sat gid=\(gid)")
            taken.append(hue)
        }
    }

    // ───────── hueOf 解析 ─────────

    func testHueOfParsesArgbIntToHue() {
        XCTAssertEqual(0, CourseColorUtil.hueOf(0xFFFF0000), accuracy: 0.01)
        XCTAssertEqual(120, CourseColorUtil.hueOf(0xFF00FF00), accuracy: 0.01)
        XCTAssertEqual(240, CourseColorUtil.hueOf(0xFF0000FF), accuracy: 0.01)
        let purpleHue = CourseColorUtil.hueOf(0xFF6750A4)
        XCTAssertTrue((240...300).contains(purpleHue), "6750A4 应在紫色区 240..300, 实测 \(purpleHue)")
        XCTAssertEqual(0, CourseColorUtil.hueOf(0xFF808080), accuracy: 0)
        XCTAssertEqual(60, CourseColorUtil.hueOf(0xFFFFFF00), accuracy: 0.01)
    }
}
