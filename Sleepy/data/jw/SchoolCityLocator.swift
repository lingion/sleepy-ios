// SchoolCityLocator.swift — ← data/jw/SchoolCityLocator.kt
// One user-initiated foreground lookup. Coordinates are never stored or logged.
//
// iOS 适配 (CoreLocation):
//   - 原版本 ACCESS_COARSE/FINE → iOS whenInUse 授权 + accuracyAuthorization
//     (.fullAccuracy→precise / .reducedAccuracy→approximate; iOS14+, min target 15.6),
//     等价 SchoolLocationPolicy.modeForPermissions(coarse, fine)。
//     providers 列表对 原版本 契约保留 "gps"/"network" 名以复用 SchoolLocationPolicy,
//     approximate 模式经 Policy.providers 排除 "gps"(与 原版本 同闸)
//   - getLastKnownLocation → CLLocationManager.location (最后一次 fix)
//   - getCurrentLocation + CancellationSignal → requestLocation + waiter 注册表:
//     iOS CLLocationManager 是单一源, 并发请求合并为一次物理请求, 结果点对分发;
//     每个 continuation 要么经 delegate 送达、要么经 withTaskCancellationHandler
//     恢复, 绝不悬挂 (对应 原 suspendCancellableCoroutine + invokeOnCancellation)
//   - SystemClock.elapsedRealtimeNanos 年龄 → 同钟差值 Date().timeIntervalSince(
//     CLLocation.timestamp)。iOS fix 只有墙钟时间戳, 用当下墙钟做差即 原版本 语义;
//     禁与 boot 基线的 systemUptime 混算(两钟相减恒为巨大负数)
//   - 12s 超时 → withTimeout 自实现 (Task sleep race)

import Foundation
import CoreLocation

final class SchoolCityLocator: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()

    /// 等待单次物理定位的登记项 — 对应 原版本 每个 getCurrentLocation
    /// 自己的 suspendCancellableCoroutine。iOS 的 CLLocationManager 是单一源:
    /// 多 waiter 合并为一次 requestLocation(), 结果点对每个 waiter 恢复。
    private struct LocationWaiter {
        let id: UInt64
        var continuation: CheckedContinuation<CLLocation?, Never>?
    }
    // 注册表主队列封闭 — delegate 回调与 begin/cancel 全部经 main queue 串行化。
    private var locationWaiters: [LocationWaiter] = []
    private var physicalRequestInFlight = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - callback 式授权 (SchoolSelectScreen 用 — 授权回调里直接续定位)

    private var permissionCompletion: ((Bool) -> Void)?

    /// 请求 WhenInUse 授权; 已授权则 completion(true) 同步回调。
    /// completion 传 nil = 清掉滞留回调(onDisappear 防泄漏)。
    /// 授权弹窗归这里(UI owns the dialog), locate() 绝不弹窗。
    func requestPermission(completion: ((Bool) -> Void)?) {
        guard let completion = completion else {
            permissionCompletion = nil
            return
        }
        switch currentAuthorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            completion(true)
        case .notDetermined:
            permissionCompletion = completion
            locationManager.requestWhenInUseAuthorization()
        default:
            completion(false)
        }
    }

    /// 单次前台定位 → 城市。坐标永不落盘、永不记日志。
    /// 与 原版本 locate() 一致: 只【检查】权限, 不弹窗;
    /// notDetermined/denied/restricted → PermissionDenied。
    func locate() async -> SchoolLocationState {
        // 权限 → mode: 原版本 modeForPermissions(coarse, fine) 的 iOS 等价 —
        // coarse = whenInUse 授权, fine = fullAccuracy;
        // .reducedAccuracy(用户在系统设置里给了"大致位置") → approximate。
        let granted = currentAuthorizationStatus == .authorizedWhenInUse
            || currentAuthorizationStatus == .authorizedAlways
        guard granted else {
            return .permissionDenied
        }
        var mode = SchoolLocationMode.precise
        if locationManager.accuracyAuthorization == .reducedAccuracy {
            mode = .approximate
        }

        guard CLLocationManager.locationServicesEnabled() else {
            return .locationDisabled
        }

        // 12s 超时 — 与 原版本 withTimeoutOrNull(12_000) 1:1
        return await withTimeout(seconds: 12) {
            await self.findCity(mode: mode)
        } ?? .positionUnavailable
    }

    private var currentAuthorizationStatus: CLAuthorizationStatus {
        // min target 15.6(iOS14+ 实例属性恒可用)
        locationManager.authorizationStatus
    }

    // MARK: - 定位到城市

    private func findCity(mode: SchoolLocationMode) async -> SchoolLocationState {
        // providers — 原版本 契约名; gps 排除/passive/去重过滤由 Lookup 内
        // SchoolLocationPolicy.providers 做, 与 原 findCity 传
        // manager.getProviders(true) 原始列表一致。
        let providers = ["gps", "network"]
        let cached: [SchoolLocationFix] = {
            guard let last = locationManager.location else { return [] }
            return [last.toFix()]
        }()
        return await SchoolLocationLookup.findCity(
            mode: mode,
            availableProviders: providers,
            cached: cached,
            loadIndex: { await self.offlineIndex() },
            requestFix: { _ in
                // iOS CLLocationManager 单一源: provider 参数不再区分物理通路,
                // 精度档由 mode 决定(原版本 侧同一 mode 下各 provider 请求同样
                // 走统一质量闸)。
                await self.requestOneFix(mode: mode)
            }
        )
    }

    /// 一次物理 requestLocation 点对多 waiter。取消语义对齐原实现
    /// invokeOnCancellation: waiter 被取消时恢复 nil 并从注册表摘除,
    /// continuation 保证恰好恢复一次(不悬挂、不双恢复)。
    private func requestOneFix(mode: SchoolLocationMode) async -> SchoolLocationFix? {
        // waiter id 每请求随机 — 不用共享计数器(请求任务跑在并发执行器上,
        // 递增会竞争); 64 位随机值在同时存活的 waiter 间碰撞概率可忽略。
        let id = UInt64.random(in: .min ... .max)
        let location = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
                beginLocationRequest(id: id, mode: mode, continuation: continuation)
            }
        } onCancel: {
            cancelLocationWaiter(id: id)
        }
        return location?.toFix()
    }

    /// 主队列操作注册表 — CLLocationManager delegate 回调默认在主线程,
    /// begin/cancel/dispatch 全部 hop 到 main 保证无竞争。
    private func beginLocationRequest(
        id: UInt64,
        mode: SchoolLocationMode,
        continuation: CheckedContinuation<CLLocation?, Never>
    ) {
        let resume: () -> Void = {
            self.locationWaiters.append(LocationWaiter(id: id, continuation: continuation))
            if self.physicalRequestInFlight { return }  // 已有物理请求在跑, 等点对分发
            self.physicalRequestInFlight = true
            self.locationManager.desiredAccuracy =
                mode == .precise ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyKilometer
            self.locationManager.requestLocation()
        }
        if Thread.isMainThread {
            resume()
        } else {
            DispatchQueue.main.async(execute: resume)
        }
    }

    private func cancelLocationWaiter(id: UInt64) {
        let cancel: () -> Void = {
            guard let idx = self.locationWaiters.firstIndex(where: { $0.id == id }) else { return }
            if let cont = self.locationWaiters[idx].continuation {
                self.locationWaiters[idx].continuation = nil
                cont.resume(returning: nil)
            }
            self.locationWaiters.remove(at: idx)
        }
        if Thread.isMainThread {
            cancel()
        } else {
            DispatchQueue.main.async(execute: cancel)
        }
    }

    private func offlineIndex() async -> OfflineSchoolCityIndex? {
        // 单飞闸 + 取消传播 — 原版本 offlineIndexLock.withLock 双检
        // @Volatile cachedOfflineIndex; 取消 = ensureActive 打断扫描。
        await withTaskCancellationHandler {
            await OfflineIndexGate.shared.index()
        } onCancel: {
            let gate = OfflineIndexGate.shared
            Task { await gate.cancelInFlight() }
        }
    }

    /// 单次解析 — 找资源 + gunzip + SCB1 流式解析。checkCancelled 把
    /// Task.isCancelled 传进 200 万点扫描(原 `{ coroutineContext.ensureActive() }`
    /// 等价): 12s 超时/任务取消可中途 abort。取消/异常/缺资源 → nil。
    fileprivate static func parseOffline() -> OfflineSchoolCityIndex? {
        // AAPT 解包 .gz 资源会去掉后缀 — iOS 侧同样 .bin.gz 优先、.bin 兜底。
        guard let url = Bundle.main.url(forResource: "school_city_boundaries", withExtension: "bin.gz")
            ?? Bundle.main.url(forResource: "school_city_boundaries", withExtension: "bin") else {
            return nil
        }
        do {
            let raw = try Data(contentsOf: url)
            let decompressed = url.pathExtension == "gz" ? (raw.gunzipped() ?? raw) : raw
            let stream = InputStream(data: decompressed)
            return try OfflineSchoolCityIndex.parse(stream) {
                if Task.isCancelled { throw OfflineSchoolCityIndex.ParseError.cancelled }
            }
        } catch {
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if let completion = permissionCompletion, status != .notDetermined {
            permissionCompletion = nil
            completion(status == .authorizedWhenInUse || status == .authorizedAlways)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        dispatchLocationFixes(locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 物理请求失败/超时取消 — 所有 waiter 收 nil(对应 原 catch → null)。
        dispatchLocationFixes([])
    }

    /// 点对分发: 每个 waiter 的 continuation 恰好恢复一次。
    private func dispatchLocationFixes(_ locations: [CLLocation]) {
        let deliver: () -> Void = {
            self.physicalRequestInFlight = false
            let waiters = self.locationWaiters
            self.locationWaiters.removeAll()
            for waiter in waiters {
                waiter.continuation?.resume(returning: locations.last)
            }
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }
}

// MARK: - 离线索引单飞闸 (对齐 原版本 companion: @Volatile cached + Mutex.withLock)

/// 进程级: 并发 locate()(双击推荐卡)只跑一次 750KB gunzip + 全量解析,
/// 其余调用 await 同一个任务; 成功后缓存。失败不缓存 — 与原实现
/// catch → null、不写 cachedOfflineIndex 一致。
private actor OfflineIndexGate {
    static let shared = OfflineIndexGate()

    private var cached: OfflineSchoolCityIndex?
    private var parseTask: Task<OfflineSchoolCityIndex?, Never>?

    func index() async -> OfflineSchoolCityIndex? {
        if let cached = cached { return cached }
        if let parseTask = parseTask { return await parseTask.value }
        // detached + .utility — 原版本 Dispatchers.IO 等价, 不占 actor 执行域。
        let task = Task.detached(priority: .utility) {
            SchoolCityLocator.parseOffline()
        }
        parseTask = task
        let result = await task.value
        parseTask = nil
        if let result = result { cached = result }
        return result
    }

    /// 取消在飞的解析 — parseOffline 的 checkCancelled 闭包读 Task.isCancelled,
    /// 可打断 200 万点扫描(原 ensureActive 等价)。
    func cancelInFlight() {
        parseTask?.cancel()
    }
}

// MARK: - helpers

private extension CLLocation {
    /// 年龄用与采样时刻同源的钟 — 原 elapsedRealtime 同钟相减的 iOS 等价物
    /// 是当下墙钟减 fix 墙钟时间戳(CLLocation 只有 Unix 时基时间戳)。
    var ageNanos: Int64 {
        Int64(max(0, Date().timeIntervalSince(timestamp)) * 1_000_000_000)
    }

    func toFix() -> SchoolLocationFix {
        SchoolLocationFix(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracyMeters: horizontalAccuracy.isFinite && horizontalAccuracy > 0
                ? Double(horizontalAccuracy) : Double.nan,
            ageNanos: ageNanos
        )
    }
}

/// withTimeout — Kotlin withTimeoutOrNull 的 Swift 实现 (nil = 超时)。
private func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping () async -> T) async -> T? {
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

// MARK: - gzip 解压 (libcompression)

import Compression

private extension Data {
    /// gunzip: 剥 gzip 容器 (RFC 1952) → raw deflate (RFC 1951) → libcompression inflate。
    /// 校验 magic; 不校验尾 CRC(与 原版本 GZIPInputStream 行为一致 — 解出即可用)。
    func gunzipped() -> Data? {
        guard count > 18, self[startIndex] == 0x1f, self[startIndex + 1] == 0x8b else {
            return nil
        }
        // gzip header: [1f 8b] [CM] [FLG] [mtime×4] [XFL] [OS] = 10 字节
        var offset = 10
        let flags = self[startIndex + 3]
        if flags & 0x04 != 0 { // FEXTRA: xlen + extra
            guard startIndex + offset + 1 < endIndex else { return nil }
            let xlen = Int(self[startIndex + offset]) | (Int(self[startIndex + offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME: 零结尾
            while offset < count && self[startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT: 零结尾
            while offset < count && self[startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset + 8 <= count else { return nil }
        // 尾 8 字节 = crc32 + isize; 中间为 raw deflate
        let deflateStart = startIndex + offset
        let deflateEnd = endIndex - 8
        guard deflateStart < deflateEnd else { return nil }
        let deflateData = subdata(in: deflateStart..<deflateEnd)
        // gzip 尾 4 字节 = ISIZE (u32 LE, 未压缩大小 mod 2^32) — 直接给出解压容量。
        let trailerISize = UInt32(self[endIndex - 4])
            | UInt32(self[endIndex - 3]) << 8
            | UInt32(self[endIndex - 2]) << 16
            | UInt32(self[endIndex - 1]) << 24
        return deflateData.inflateRawDeflate(suggestedCapacity: Int(trailerISize))
    }

    // BUGFIX(2026-10-26): 旧实现用 FINALIZE 流式循环, dst 缓冲(64KB)写满时
    // compression_stream_process 直接返回 COMPRESSION_STATUS_ERROR(而非 OK),
    // 任何解压产物 >64KB 的数据必然失败 → 城市边界库(1.3MB)永远解不开
    // → gunzipped() ?? raw 静默回落压缩字节 → SCB1 魔数解析失败
    // → 定位推荐恒显示"未匹配到城市"。改为 decode_buffer 一次性解码,
    // 容量优先用 ISIZE, 不可靠(0/>4G 回绕)时倍增重试兜底。
    private func inflateRawDeflate(suggestedCapacity: Int) -> Data? {
        var src = [UInt8](self)
        // Data extension 内裸 max 会解析到 Sequence.max() 实例方法 — 显式 Swift.max
        var capacity = Swift.max(suggestedCapacity, 64 * 1024)
        let maxCapacity = 512 * 1024 * 1024
        while capacity <= maxCapacity {
            var dst = [UInt8](repeating: 0, count: capacity)
            let n = src.withUnsafeMutableBufferPointer { sp -> Int in
                dst.withUnsafeMutableBufferPointer { dp in
                    compression_decode_buffer(
                        dp.baseAddress!, capacity,
                        sp.baseAddress!, sp.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if n == 0 { return nil } // 真错误(容量未满仍失败)
            if n < capacity { return Data(bytes: dst, count: n) }
            capacity *= 2           // 恰好写满 → 扩容重试
        }
        return nil
    }
}
