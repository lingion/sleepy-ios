// CourseColorWriteGlue.swift — ← util/CourseColorWriteGlue.kt (v1.0.62 B1)
//
// 派生档写侧胶水（spec §2.4「新课按当前模式算 hue 写表」）。
//
// 渲染层保持纯读（persistedHue ?: stableHue）; course_colors 写入只发生在
// 课程组**诞生**时刻: 教务导入 / 文件导入 / 覆盖导入 / 单课新增。
//
// 红线（spec §2.1/§2.3）:
//   - CLASSIC 档（anchor=null）绝不写表 — 升级零变化, course_colors 保持空;
//   - 钉死性: 既有组 hue 永不被本胶水移动, 只给「表中查无」的新组补色;
//   - 配色是增值数据: 读写异常一律吞掉降级为不写,
//     绝不允许影响课程落库主流程（查无 hue → 渲染回落 stableHue 老路径,
//     step-5 主题重算/手动重排可自愈）。

import Foundation
import GRDB
import SwiftUI

enum CourseColorWriteGlue {

    /// 同步入口：返回前完成写库；注入偏好用于导入及隔离测试。
    @discardableResult
    static func persistNewGroupHues(
        dao: CourseColorDao, entities: [CourseEntity], prefs: AppPrefs = .shared
    ) -> [String: Float] {
        let mode = prefs.getCourseColorMode()
        return persistSynchronously(mode: mode, anchor: resolveAnchor(mode: mode, prefs: prefs),
                                    dao: dao, entities: entities)
    }

    /// 兼容显式 mode/anchor 的 async 调用者；写入仍在返回前完成。
    @discardableResult
    static func persistNewGroupHues(
        mode: Int,
        anchor: Float?,
        dao: CourseColorDao,
        entities: [CourseEntity]
    ) async -> [String: Float] {
        persistSynchronously(mode: mode, anchor: anchor, dao: dao, entities: entities)
    }

    private static func persistSynchronously(
        mode: Int, anchor: Float?, dao: CourseColorDao, entities: [CourseEntity]
    ) -> [String: Float] {
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC, let anchor else { return [:] }
        do {
            // 读旧色、规划和写入串行于同一事务，避免并发导入覆盖已有色相。
            return try dao.db.write { dbw in
                try persistInDb(dbw, mode: mode, anchor: anchor, dao: dao, entities: entities)
            }
        } catch {
            return [:] // 配色失败同步降级，绝不返回尚未持久化的规划。
        }
    }

    /// 已在导入事务内时必须走此入口；成功值仍随外层事务提交或回滚。
    @discardableResult
    static func persistNewGroupHuesInDb(
        dbw: Database, dao: CourseColorDao, entities: [CourseEntity], prefs: AppPrefs = .shared
    ) -> [String: Float] {
        let mode = prefs.getCourseColorMode()
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC,
              let anchor = resolveAnchor(mode: mode, prefs: prefs) else { return [:] }
        do {
            return try persistInDb(dbw, mode: mode, anchor: anchor, dao: dao, entities: entities)
        } catch {
            return [:] // savepoint 撤回本批颜色，保留外层课程导入。
        }
    }

    private static func persistInDb(
        _ dbw: Database, mode: Int, anchor: Float, dao: CourseColorDao, entities: [CourseEntity]
    ) throws -> [String: Float] {
        // 读取失败必须传播到降级边界，不能当成空表覆盖旧色。
        let persisted = try dao.getHueMapInDb(dbw, CourseColorEntity.GLOBAL_TABLE_KEY)
        let newGids = distinctNonBlank(entities.map { $0.groupId }).filter { persisted[$0] == nil }
        let plan = CourseColorUtil.planHuesForGroups(
            anchor: anchor, existingHues: Array(persisted.values), gids: newGids
        )
        return try writePlan(plan, in: dbw, mode: mode, dao: dao)
    }

    /// 全表重算（spec §2.3 时机 1/2/3/6 — 模式切换/主题变化/种子变化/手动重排）:
    /// 以 anchor 对全部非空白、去重 groupId 重新编排 hue 并 REPLACE 落库。
    /// anchor=nil → 零写；0° 是合法色相。
    @discardableResult
    static func recalcWithAnchor(
        anchor: Float?,
        dao: CourseColorDao,
        gids: [String]
    ) -> [String: Float] {
        recalcSynchronously(anchor: anchor, mode: AppPrefs.shared.getCourseColorMode(), dao: dao, gids: gids)
    }

    private static func recalcSynchronously(
        anchor: Float?, mode: Int, dao: CourseColorDao, gids: [String]
    ) -> [String: Float] {
        guard let anchor else { return [:] }
        let plan = CourseColorUtil.planHuesForGroups(
            anchor: anchor, existingHues: [], gids: distinctNonBlank(gids)
        )
        guard !plan.isEmpty else { return [:] }
        do {
            return try dao.db.write { dbw in
                try writePlan(plan, in: dbw, mode: mode, dao: dao)
            }
        } catch {
            return [:]
        }
    }

    private static func distinctNonBlank(_ gids: [String]) -> [String] {
        var seen = Set<String>()
        // 空白判断复用跨端口径；非空 groupId 不 trim，避免改变课程身份。
        return gids.filter { CourseColorUtil.isNotBlank($0) && seen.insert($0).inserted }
    }

    private static func writePlan(
        _ plan: [String: Float], in dbw: Database, mode: Int, dao: CourseColorDao
    ) throws -> [String: Float] {
        guard !plan.isEmpty else { return [:] }
        try dbw.inSavepoint {
            try dao.upsertAllInDb(dbw, plan.map {
                CourseColorEntity(groupId: $0.key, hue: $0.value)
            })
            // 只在外层提交后通知缓存，回滚不得发布未提交颜色。
            dbw.afterNextTransaction { _ in
                Task { @MainActor in CourseHueStore.shared.invalidate(mode: mode, dao: dao) }
            }
            return .commit
        }
        return plan
    }

    @discardableResult
    static func recalcAll(dao: CourseColorDao, gids: [String], prefs: AppPrefs = .shared) -> Int {
        let mode = prefs.getCourseColorMode()
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC else { return 0 }
        return recalcSynchronously(anchor: resolveAnchor(mode: mode, prefs: prefs), mode: mode,
                                   dao: dao, gids: gids).count
    }

    /// Context 系重算入口（AppearanceScreen/主题挂钩调用）。返回重算组数。
    static func recalcAll(
        mode: Int, dao: CourseColorDao, gids: [String]
    ) async -> Int {
        if mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC { return 0 }
        let anchor = resolveAnchor(mode: mode)
        if anchor == nil { return 0 }
        return recalcSynchronously(anchor: anchor, mode: mode, dao: dao, gids: gids).count
    }

    /// 当前深浅档主题 primary 的 anchor 解析 — 与 SwiftUI 渲染路径同一派生函数。
    ///   system → 共享窗口 tint 快照，经统一 HSV/M3 角色解析器;
    ///   custom:<id> → CustomSchemeDeriver.derive(...) 同一函数;
    ///   其他 → ThemePresets.byKey 取深浅 primary。
    static func resolveAnchor(mode: Int, prefs: AppPrefs = .shared,
                              systemSnapshot: SystemColorSnapshot? = nil) -> Float? {
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC,
              let primaryColor = currentThemePrimaryColor(prefs: prefs, systemSnapshot: systemSnapshot) else { return nil }
        let argb = prefs.getThemeKey() == ThemePresets.KEY_SYSTEM
            ? SystemColorScheme.argb(primaryColor) : colorToArgb(primaryColor)
        let seedHue = prefs.getCourseColorSeedHue()
        return CourseColorUtil.resolveAnchor(mode: mode, themePrimaryArgb: argb, seedHue: seedHue)
    }

    /// 解析当前主题(primary)颜色。
    /// system 使用与 App/Widget 同源快照；缺失时显式默认种子回落。
    /// custom:<id>→CustomSchemeDeriver.derive 同一派生; 其他→ThemePresets 当前深浅 primary。
    private static func currentThemePrimaryColor(prefs: AppPrefs, systemSnapshot: SystemColorSnapshot?) -> Color? {
        let themeKey = prefs.getThemeKey()
        let isDark = prefs.isDarkMode()
        if themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
            let id = String(themeKey.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
            let seed = CustomThemeStore.getById(id) ?? defaultSeedTheme()
            return CustomSchemeDeriver.derive(theme: seed, isDark: isDark).primary
        } else if themeKey == ThemePresets.KEY_SYSTEM {
            // 只在既有显式操作中读取；系统信号发布不触发课程 DB 重算。
            let snapshot = systemSnapshot ?? SystemColorSeedStore.read()
            return SystemColorScheme.resolve(snapshot: snapshot,
                dark: prefs.isDarkMode(isSystemDark: snapshot.systemDark)).primary
        } else {
            let preset = ThemePresets.byKey(themeKey)
            return isDark ? preset.dark.primary : preset.light.primary
        }
    }

    /// custom:<id> id 读不到(已删)时回落种子 = 默认淡紫 (Theme.kt)。
    private static func defaultSeedTheme() -> CustomTheme {
        CustomTheme(
            id: "", name: "", primary: "#6750A4", secondary: "#625B71",
            tertiary: "#7D5260", surfaceHue: 265.0, surfaceChroma: 8.0, createdAt: 0
        )
    }

    /// Color → ARGB Int (0xAARRGGBB) — 手拼, 同 CourseColorUtil.hueOf 的 ARGB 分支。
    private static func colorToArgb(_ color: Color) -> Int {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(a * 255) << 24) | (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }
}

// MARK: - 平台无关的 Array distinct 助手

extension Array where Element: Hashable {
    func distinct<T: Hashable>(_ keyPath: KeyPath<Element, T>) -> [Element] {
        var seen: Set<T> = []
        var result: [Element] = []
        for element in self {
            let key = element[keyPath: keyPath]
            if !seen.contains(key) {
                seen.insert(key)
                result.append(element)
            }
        }
        return result
    }
}
