// SchoolLocationLookup.swift — ← data/jw/SchoolLocationLookup.kt
// Provider race independent of platform APIs, including cancellation and city quality checks.
//
// iOS 适配: Kotlin coroutineScope/Channel → Swift withTaskGroup。
// 语义 1:1:
//   - 索引加载与每个 provider 的请求同时启动 (Android async + launch);
//   - 实时 fix 按【完成顺序】收取 (Android Channel(capacity=providers.size) 缓冲 +
//     repeat(size) { receive() }), 快网络 fix 不被慢 GPS 挡住;
//   - 任何返回路径都取消全部子请求 (Android finally { indexRequest.cancel();
//     requests.forEach { it.cancel() } }); withTaskGroup 作用域结束时对残留
//     子任务 cancel + await, 外层任务被取消("离开页面")时子任务自动继承取消。
//   - 缓存 gate 在索引就绪之后、实时收取之前, 每个结果过 usable 质量闸 +
//     city 8 方向采样; 拒绝原因记入 rejected, 全部失败时返回最具体的拒绝原因。

import Foundation

enum SchoolLocationState: Equatable {
    case idle
    case locating
    case ready(city: String)
    case permissionDenied
    case accuracyInsufficient
    case locationDisabled
    case positionUnavailable
    case unavailable
}

enum SchoolLocationLookup {

    /// 单一事件流: 索引就绪 或 某 provider 的 fix (nil = 失败/无结果)。
    private enum RaceEvent {
        case index(OfflineSchoolCityIndex?)
        case fix(SchoolLocationFix?)
    }

    static func findCity(
        mode: SchoolLocationMode,
        availableProviders: [String],
        cached: [SchoolLocationFix],
        loadIndex: @escaping () async -> OfflineSchoolCityIndex?,
        requestFix: @escaping (_ provider: String) async -> SchoolLocationFix?
    ) async -> SchoolLocationState {
        let providers = SchoolLocationPolicy.providers(mode: mode, available: availableProviders)
        if providers.isEmpty { return .positionUnavailable }

        return await withTaskGroup(of: RaceEvent.self, returning: SchoolLocationState.self) { group in
            // 索引与各 provider 请求并发启动; requestFix 闭包内错误自吞
            // (Android catch (_: Exception) { null } — Swift 非 throwing 签名由闭包侧负责)
            group.addTask(priority: .userInitiated) {
                RaceEvent.index(await loadIndex())
            }
            for provider in providers {
                group.addTask(priority: .userInitiated) {
                    RaceEvent.fix(await requestFix(provider))
                }
            }

            // 1. 先等索引 (Android indexRequest.await())。
            //    期间完成的实时 fix 按完成顺序 FIFO 缓冲
            //    (= Channel(providers.size) 容量恰好装下全部结果, 发送不挂起)。
            var loadedIndex: OfflineSchoolCityIndex?
            var bufferedFixes: [SchoolLocationFix?] = []
            var indexSeen = false
            while !indexSeen {
                guard let event = await group.next() else { break }
                switch event {
                case .index(let index):
                    loadedIndex = index
                    indexSeen = true
                case .fix(let fix):
                    bufferedFixes.append(fix)
                }
                if Task.isCancelled { break }
            }
            guard indexSeen, let index = loadedIndex else {
                // Android: index null → Unavailable; finally 取消全部请求
                group.cancelAll()
                return .unavailable
            }

            // 拒绝原因跟踪: accuracyInsufficient > unavailable > positionUnavailable
            var rejected = SchoolLocationState.positionUnavailable

            func resolve(_ fix: SchoolLocationFix?) -> SchoolLocationState? {
                guard let fix = fix else { return nil }
                if !SchoolLocationPolicy.usable(mode: mode, fix: fix) {
                    if fix.ageNanos >= 0 && fix.ageNanos <= 30_000_000_000 {
                        rejected = .accuracyInsufficient
                    }
                    return nil
                }
                let cityFix = SchoolLocationPolicy.forCityLookup(mode: mode, fix: fix)
                if let city = SchoolLocationPolicy.city(index: index, fix: cityFix) {
                    return .ready(city: city)
                }
                if index.cityAt(latitude: cityFix.latitude, longitude: cityFix.longitude) != nil {
                    rejected = .accuracyInsufficient
                } else if case .accuracyInsufficient = rejected {
                    // keep
                } else {
                    rejected = .unavailable
                }
                return nil
            }

            // 2. 索引就绪后先扫缓存 (年龄升序 → 精度升序)
            let recent = cached
                .filter { SchoolLocationPolicy.usable(mode: mode, fix: $0) }
                .sorted { a, b in
                    if a.ageNanos != b.ageNanos { return a.ageNanos < b.ageNanos }
                    return a.accuracyMeters < b.accuracyMeters
                }
            for fix in recent {
                if let result = resolve(fix) {
                    group.cancelAll()
                    return result
                }
            }

            // 3. 实时 fix 按完成顺序收取 (Android repeat(size){ receive() });
            //    缓冲阶段已收的先按序处理, 其余随到随处理
            for fix in bufferedFixes {
                if let result = resolve(fix) {
                    group.cancelAll()
                    return result
                }
            }
            var received = bufferedFixes.count
            while received < providers.count {
                guard let event = await group.next() else { break }
                switch event {
                case .index:
                    continue // 索引只送达一次, 已在阶段 1 消费
                case .fix(let fix):
                    received += 1
                    if let result = resolve(fix) {
                        group.cancelAll()
                        return result
                    }
                }
                if Task.isCancelled {
                    // 外层任务被取消("离开页面") — Android receive() 抛
                    // CancellationException → finally 取消全部请求。
                    // 非 throwing 签名下的等价: 立即收敛, 作用域结束取消残留子任务。
                    break
                }
            }
            group.cancelAll()
            return rejected
        }
    }
}
