// CourseHueStore.swift — ← util/CourseHueStore.kt (v1.0.62, GPL-3.0)
// 持久色相只读缓存 — course_colors 全表 gid→hue 的进程级快照。
//
// 渲染入口拿 `hueFor(groupId)` 作 persistedHue 注入四个 pickCourseColor* 入口:
//   - CLASSIC 档或查无 → nil → 走 v1.0.61 stableHue 老路径(零变化);
//   - 派生档命中 → 表值(认亲/重算写入的色相)。
//
// 刷新源(全部 IO, 渲染叶子同步读快照零开销):
//   ① 应用启动 start() 首载 + AppPrefs 的 mode/seed/theme/themeMode 变更;
//   ② 写侧显式 invalidate()(导入补色/重算,事务提交后调用);
//   ③ 小组件装载点 refresh()(widget 进程与 app 进程分离,装载点自刷保证同帧一致)。
//
// 失败语义: 表读失败 → 空快照 → 全线回落 stableHue。配色是增值数据,
// 任何异常不得影响课程渲染主流程。
//
// ★ ObservableObject / @Published: Android 侧 CourseHueStore 是 MutableStateFlow,
//   Compose 叶节点 collectAsState 订阅 → 快照变化自动重组。iOS 等价物 = 本类
//   暴露 @Published 快照, 渲染叶子以 @ObservedObject 订阅 → 换色后同帧刷新。

import Foundation
import Combine
import UIKit

final class CourseHueStore: ObservableObject {
    static let shared = CourseHueStore()

    private let lock = NSLock()
    /// 快照真值(非 @Published 的那份; @Published 名为 hueMap, 合成存储 storedHueMap)
    private var storedHueMap: [String: Float] = [:]

    /// 快照(渲染叶子订阅) — 变化即触发视图刷新。
    @Published private(set) var hueMap: [String: Float] = [:]

    /// 快照变化即推送(Compose collectAsState ↔ Combine 订阅)
    var hueMapPublisher: AnyPublisher<[String: Float], Never> {
        $hueMap.eraseToAnyPublisher()
    }

    /// 同步取持久 hue(CLASSIC/查无 → nil)
    func hueFor(_ groupId: String) -> Float? {
        lock.lock(); defer { lock.unlock() }
        return storedHueMap[groupId]
    }

    /// 当前快照副本
    var currentHueMap: [String: Float] {
        lock.lock(); defer { lock.unlock() }
        return storedHueMap
    }

    private var started = false
    private var cancellables: Set<AnyCancellable> = []

    /// 幂等启动 — AppDelegate 调一次。
    func start(prefs: AppPrefs = .shared) {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        let prefs = prefs
        let subs = [
            prefs.courseColorModePublisher.sink { [weak self] _ in self?.scheduleRefresh() },
            prefs.courseColorSeedHuePublisher.sink { [weak self] _ in self?.scheduleRefresh() },
            prefs.themeKeyPublisher.sink { [weak self] _ in self?.scheduleRefresh() },
            prefs.themeModePublisher.sink { [weak self] _ in self?.scheduleRefresh() },
        ]
        DispatchQueue.main.async {
            for c in subs { self.cancellables.insert(c) }
        }
        scheduleRefresh()
    }

    /// 写侧(补色/重算)事务提交后调用 — 触发后台重读。
    func invalidate() {
        scheduleRefresh()
    }

    /// 直读 course_colors 并更新快照。CLASSIC 档 → 空快照(红线: 渲染零变化)。
    func refresh(prefs: AppPrefs = .shared, database: AppDatabase? = nil) {
        let mode = prefs.getCourseColorMode()
        var map: [String: Float] = [:]
        if mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC {
            let db = database ?? AppDatabase.getShared()
            map = (try? db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)) ?? [:]
        }
        lock.lock()
        storedHueMap = map
        lock.unlock()
        publish(map)
    }

    /// @Published 只能在主线程更新 — 后台刷新时切主线程。
    private func publish(_ map: [String: Float]) {
        if Thread.isMainThread {
            if hueMap != map { hueMap = map }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.hueMap != map { self.hueMap = map }
            }
        }
    }

    /// 后台重读 — IO 不在渲染线程
    private func scheduleRefresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.refresh()
        }
    }
}
