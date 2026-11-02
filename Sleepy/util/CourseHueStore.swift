// CourseHueStore.swift — ← util/CourseHueStore.kt (v1.0.62 B1)
//
// 持久色相只读缓存（spec §2.1/§2.3 渲染层）— course_colors 全表 gid→hue 的进程级快照。
//
// 渲染入口拿 `hueFor(groupId)` 作 persistedHue 注入四入口:
//   - CLASSIC 档或查无 → nil → pickCourseColor* 走 v1.0.61 stableHue 老路径（零变化）;
//   - 派生档命中 → 表值（认亲/重算写入的色相）。
//
// 刷新源:
//   ① 应用启动首载 + 主题色模式键变化时重载;
//   ② 写侧(CourseColorWriteGlue)事务提交后 invalidate;
//   ③ widget 装载时 refresh。
//
// 失败语义: 表读失败 → 空快照 → 全线回落 stableHue。
// 配色是增值数据, 任何异常不得影响课程渲染主流程。

import Foundation
import GRDB
import SwiftUI

/// 进程级持久色相缓存 — 单例, iOS 无 changeBus 用 NotificationCenter 通知刷新。
@MainActor
final class CourseHueStore: ObservableObject {
    static let shared = CourseHueStore()

    // 渲染层 collectAsState 等价: @Published 触发重组/重绘
    @Published private(set) var hueMap: [String: Float] = [:]

    /// 单次读取持久 hue（CLASSIC/查无 → nil）。
    static func hueFor(groupId: String) -> Float? {
        shared.hueMap[groupId]
    }

    private init() {}

    /// 直读 course_colors 并更新快照。CLASSIC 档 → 空快照（红线: 渲染零变化,
    /// 模式切换钩子在切出 CLASSIC 时经 invalidate 重灌）。
    func refresh(mode: Int, dao: CourseColorDao?) async {
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC, let dao else {
            await MainActor.run { hueMap = [:] }
            return
        }
        let map = (try? dao.getHueMap(CourseColorEntity.GLOBAL_TABLE_KEY)) ?? [:]
        await MainActor.run { hueMap = map }
        // 通知监听者(渲染层/AppearanceScreen)快照已刷新
        NotificationCenter.default.post(name: .courseHueStoreChanged, object: nil)
    }

    /// 写侧(invalidator)事务提交后调用 — 触发后台重读。
    /// iOS 上无协程作用域, 由调用方自行在 async 上下文调用 refresh。
    func invalidate(mode: Int, dao: CourseColorDao?) {
        Task {
            await refresh(mode: mode, dao: dao)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let courseHueStoreChanged = Notification.Name("courseHueStoreChanged")
}
