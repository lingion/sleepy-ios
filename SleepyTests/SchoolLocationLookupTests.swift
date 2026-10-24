// SchoolLocationLookupTests.swift — ← SchoolLocationLookupTest.kt (v1.0.61)
//
// 六个用例逐一对应 Android 侧 SchoolLocationLookupTest:
//   1. 快的 network 城市结果无需等 GPS, 且 GPS 请求被取消
//   2. 全部实时 provider 还在等时, 近期合格缓存直接命中
//   3. 快的粗精度结果不能击败慢的高精度结果
//   4. approximate 模式从不启动 GPS provider
//   5. 离开页面(外层任务取消)取消每一个挂起 provider
//   6. 区域外粗精度 vs 无结果 — 结局彼此不同 (Unavailable /
//      AccuracyInsufficient / PositionUnavailable)
//
// 索引 fixture: Kotlin SchoolBoundaryFixture 把 JSON 编成 SCB1 字节流;
// iOS 侧直接按同一格式手拼 Data(区域 "A" = [0,1]×[0,1] 度, 坐标×10000)。

import Foundation
import XCTest
@testable import Sleepy

final class SchoolLocationLookupTests: XCTestCase {

    // MARK: - fixture

    /// SCB1: magic + areaCount + (nameLen, name, polygonCount, ringCount, pointCount, int32×2 per point)
    private static func boundaryIndexJSON() -> Data {
        // JSON 等价物: {"areas":[{"name":"A","polygons":[[[[0,0],[1,0],[1,1],[0,1],[0,0]]]]}]}
        // 点为 [longitude, latitude], 度×10000。
        let points: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]
        var data = Data()
        func i32(_ v: Int32) {
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        i32(0x53434231) // "SCB1"
        i32(1)          // areas
        let name = Array("A".utf8)
        i32(Int32(name.count))
        data.append(contentsOf: name)
        i32(1)          // polygons
        i32(1)          // rings
        i32(Int32(points.count))
        for (lng, lat) in points {
            i32(Int32((lng * 10_000).rounded()))
            i32(Int32((lat * 10_000).rounded()))
        }
        return data
    }

    private func makeIndex() throws -> OfflineSchoolCityIndex {
        let stream = InputStream(data: Self.boundaryIndexJSON())
        return try OfflineSchoolCityIndex.parse(stream)
    }

    private var sample: SchoolLocationFix {
        SchoolLocationFix(latitude: 0.5, longitude: 0.5, accuracyMeters: 30.0, ageNanos: 0)
    }

    // MARK: - 并发测试基元 (对应 Kotlin CompletableDeferred / 计数器)

    /// 一次性门闸 — Kotlin CompletableDeferred<Unit> 的等价物: signal 前挂起, signal 后立即放行。
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var signaled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func signal() {
            lock.lock()
            let pending = waiters
            waiters = []
            signaled = true
            lock.unlock()
            for w in pending { w.resume() }
        }

        func wait() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                register(c)
            }
        }

        /// 同步登记 — 已 signal 直接放行, 否则排队 (NSLock 只在同步域使用)。
        private func register(_ c: CheckedContinuation<Void, Never>) {
            lock.lock()
            if signaled {
                lock.unlock()
                c.resume()
            } else {
                waiters.append(c)
                lock.unlock()
            }
        }
    }

    /// 线程安全计数器/标志集合。
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var counters: [String: Int] = [:]
        private var pendingWaiters: [(key: String, cont: CheckedContinuation<Void, Never>)] = []

        func bump(_ key: String) {
            lock.lock()
            counters[key, default: 0] += 1
            let ready = pendingWaiters.filter { $0.key == key }
            pendingWaiters.removeAll { $0.key == key }
            lock.unlock()
            for w in ready { w.cont.resume() }
        }

        func count(_ key: String) -> Int {
            lock.lock()
            let v = counters[key] ?? 0
            lock.unlock()
            return v
        }

        /// 挂起直到 key 被 bump 至少 min 次 (已满足则立即返回)。
        func waitUntil(_ key: String, atLeast min: Int) async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                register(key, min, c)
            }
        }

        /// 同步登记 — 已达阈值直接放行, 否则排队 (NSLock 只在同步域使用)。
        private func register(_ key: String, _ min: Int, _ c: CheckedContinuation<Void, Never>) {
            lock.lock()
            if (counters[key] ?? 0) >= min {
                lock.unlock()
                c.resume()
            } else {
                pendingWaiters.append((key, c))
                lock.unlock()
            }
        }
    }

    /// 挂起直到外层任务被取消 (对应 Kotlin CompletableDeferred().await() + finally)。
    private func awaitCancellation(box: Box, key: String) async {
        box.bump(key + ".started")
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        box.bump(key + ".cancelled")
    }

    // MARK: - 1. 快 network 不等 GPS 且取消 GPS

    func testFastNetworkCityReturnsWithoutWaitingForGPSAndCancelsGPS() async throws {
        let index = try makeIndex()
        let box = Box()
        let result = await withTimeout(seconds: 2) {
            await SchoolLocationLookup.findCity(
                mode: .precise,
                availableProviders: ["gps", "network"],
                cached: [],
                loadIndex: { index },
                requestFix: { provider in
                    if provider == "gps" {
                        await self.awaitCancellation(box: box, key: "gps")
                        return nil
                    }
                    return self.sample
                })
        }
        XCTAssertEqual(result, .ready(city: "A"))
        XCTAssertGreaterThanOrEqual(box.count("gps.started"), 1)
        XCTAssertGreaterThanOrEqual(box.count("gps.cancelled"), 1)
    }

    // MARK: - 2. 全部 provider 挂起时近期缓存命中

    func testRecentQualifiedCacheReturnsWhileAllLiveProvidersWait() async throws {
        let index = try makeIndex()
        let result = await withTimeout(seconds: 2) {
            await SchoolLocationLookup.findCity(
                mode: .precise,
                availableProviders: ["gps", "network"],
                cached: [self.sample],
                loadIndex: { index },
                requestFix: { _ in
                    // 永不返回, 直到被取消
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                    return nil
                })
        }
        XCTAssertEqual(result, .ready(city: "A"))
    }

    // MARK: - 3. 快粗精度不能击败慢高精度

    func testFastInaccurateResultCannotBeatSlowerPreciseResult() async throws {
        let index = try makeIndex()
        let gate = Gate()
        let stale = SchoolLocationFix(latitude: 0.5, longitude: 0.5, accuracyMeters: 30.0,
                                      ageNanos: 60_000_000_000)
        let result = await SchoolLocationLookup.findCity(
            mode: .precise,
            availableProviders: ["gps", "network"],
            cached: [stale],
            loadIndex: { index },
            requestFix: { provider in
                if provider == "network" {
                    gate.signal()
                    return SchoolLocationFix(latitude: 0.5, longitude: 0.5,
                                             accuracyMeters: 5_000.0, ageNanos: 0)
                }
                await gate.wait()
                return self.sample
            })
        XCTAssertEqual(result, .ready(city: "A"))
    }

    // MARK: - 4. approximate 从不启动 GPS

    func testApproximateNeverStartsTheGPSProvider() async throws {
        let index = try makeIndex()
        let box = Box()
        let result = await SchoolLocationLookup.findCity(
            mode: .approximate,
            availableProviders: ["gps", "network"],
            cached: [],
            loadIndex: { index },
            requestFix: { provider in
                box.bump("requested." + provider)
                return self.sample
            })
        XCTAssertEqual(result, .ready(city: "A"))
        XCTAssertEqual(box.count("requested.network"), 1)
        XCTAssertEqual(box.count("requested.gps"), 0)
    }

    // MARK: - 5. 离开页面取消全部挂起 provider

    func testLeavingThePageCancelsEveryPendingProvider() async throws {
        let index = try makeIndex()
        let box = Box()
        let lookup = Task {
            await SchoolLocationLookup.findCity(
                mode: .precise,
                availableProviders: ["gps", "network"],
                cached: [],
                loadIndex: { index },
                requestFix: { _ in
                    await self.awaitCancellation(box: box, key: "p")
                    return nil
                })
        }
        // Kotlin: 两个 provider 都启动后再取消 (starts == 2)
        let startedInTime = await withTimeout(seconds: 2) { () -> Bool in
            await box.waitUntil("p.started", atLeast: 2)
            return true
        }
        XCTAssertEqual(startedInTime, true)
        // 两 provider 都挂起, findCity 此时不应已返回 — 外层取消 = "离开页面"
        lookup.cancel()
        let final = await withTimeout(seconds: 2) { await lookup.value }
        XCTAssertNotNil(final, "取消后 findCity 必须收敛, 不得悬挂")
        XCTAssertEqual(box.count("p.started"), 2)
        XCTAssertEqual(box.count("p.cancelled"), 2)
    }

    // MARK: - 6. 区域外粗精度与无结果结局不同

    func testOutsideImpreciseAndAbsentResultsHaveDistinctOutcomes() async throws {
        let index = try makeIndex()

        func result(_ fix: SchoolLocationFix?) async -> SchoolLocationState? {
            await withTimeout(seconds: 2) {
                await SchoolLocationLookup.findCity(
                    mode: .precise,
                    availableProviders: ["network"],
                    cached: [],
                    loadIndex: { index },
                    requestFix: { _ in fix })
            }
        }

        let outside = SchoolLocationFix(latitude: 20.0, longitude: 0.5,
                                       accuracyMeters: 30.0, ageNanos: 0)
        let r1 = await result(outside)
        XCTAssertEqual(r1, .unavailable)

        let imprecise = SchoolLocationFix(latitude: 0.5, longitude: 0.5,
                                          accuracyMeters: 5_000.0, ageNanos: 0)
        let r2 = await result(imprecise)
        XCTAssertEqual(r2, .accuracyInsufficient)

        let r3 = await result(nil)
        XCTAssertEqual(r3, .positionUnavailable)

        let edgeAmbiguous = SchoolLocationFix(latitude: 0.5, longitude: 0.999,
                                              accuracyMeters: 500.0, ageNanos: 0)
        let r4 = await result(edgeAmbiguous)
        XCTAssertEqual(r4, .accuracyInsufficient)
    }

    // MARK: - helpers

    /// Kotlin withTimeout(2_000) 的等价物: 超时返回 nil。
    private func withTimeout<T: Sendable>(seconds: Double,
                                         _ body: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
