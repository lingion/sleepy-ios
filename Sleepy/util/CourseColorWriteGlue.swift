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

    /// 为 entities 中的新组补持久 hue（既有组只读跳过）; 返回本次写入的 gid→hue。
    static func persistNewGroupHues(
        mode: Int,
        anchor: Float?,
        dao: CourseColorDao,
        entities: [CourseEntity]
    ) async -> [String: Float] {
        (try? await dao.db.write { dbw in
            persistNewGroupHuesInDb(dbw: dbw, dao: dao, entities: entities,
                                   mode: mode, anchor: anchor)
        }) ?? [:]
    }

    /// 同步导入入口；读取、规划和补色共用一次写事务，避免并发覆盖既有色相。
    @discardableResult
    static func persistNewGroupHues(
        dao: CourseColorDao, entities: [CourseEntity], prefs: AppPrefs = .shared
    ) -> [String: Float] {
        (try? dao.db.write { dbw in
            persistNewGroupHuesInDb(dbw: dbw, dao: dao, entities: entities, prefs: prefs)
        }) ?? [:]
    }

    /// 已在导入事务内时只使用 dbw，绝不重入 DatabaseQueue。
    @discardableResult
    static func persistNewGroupHuesInDb(
        dbw: Database, dao: CourseColorDao, entities: [CourseEntity], prefs: AppPrefs = .shared
    ) -> [String: Float] {
        let mode = prefs.getCourseColorMode()
        return persistNewGroupHuesInDb(dbw: dbw, dao: dao, entities: entities,
                                      mode: mode, anchor: resolveAnchor(mode: mode, prefs: prefs))
    }

    private static func persistNewGroupHuesInDb(
        dbw: Database, dao: CourseColorDao, entities: [CourseEntity], mode: Int, anchor: Float?
    ) -> [String: Float] {
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC, let anchor else { return [:] }
        do {
            let rows = try CourseColorEntity.fetchAll(dbw,
                sql: "SELECT * FROM course_colors WHERE tableKey = ?",
                arguments: [CourseColorEntity.GLOBAL_TABLE_KEY])
            let persisted = Dictionary(uniqueKeysWithValues: rows.map { ($0.groupId, $0.hue) })
            let gids = entities.map(\.groupId)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && persisted[$0] == nil }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let plan = CourseColorUtil.planHuesForGroups(
                anchor: anchor, existingHues: Array(persisted.values), gids: gids)
            guard !plan.isEmpty else { return [:] }
            // 配色失败不影响课程，但同批补色不能留下部分成功的行。
            try dbw.inSavepoint {
                for (gid, hue) in plan {
                    var row = CourseColorEntity(groupId: gid, hue: hue)
                    try row.insert(dbw)
                }
                return .commit
            }
            dbw.afterNextTransaction { _ in
                Task { @MainActor in CourseHueStore.shared.invalidate(mode: mode, dao: dao) }
            }
            return plan
        } catch {
            return [:]
        }
    }

    /// 全表重算（spec §2.3 时机 1/2/3/6 — 模式切换/主题变化/种子变化/手动重排）:
    /// 以 anchor 对全部非空白、去重 groupId 重新编排 hue 并 REPLACE 落库。
    /// anchor=0(COLOR 模式 0) → 零写 — 表不动, 渲染走 stableHue。
    static func recalcWithAnchor(
        anchor: Float?,
        dao: CourseColorDao,
        gids: [String]
    ) -> [String: Float] {
        let distinct = gids.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if anchor == nil { return [:] } // CLASSIC → 零写
        let plan = CourseColorUtil.planHuesForGroups(
            anchor: anchor, existingHues: [], gids: distinct
        )
        if !plan.isEmpty {
            let rows = plan.map { (gid, hue) in
                CourseColorEntity(tableKey: CourseColorEntity.GLOBAL_TABLE_KEY, groupId: gid, hue: hue)
            }
            do {
                try dao.upsertAll(rows)
                Task { @MainActor in
                    CourseHueStore.shared.invalidate(mode: AppPrefs.shared.getCourseColorMode(), dao: dao)
                }
            } catch {
                return [:]
            }
        }
        return plan
    }

    /// Context 系重算入口（AppearanceScreen/主题挂钩调用）。返回重算组数。
    static func recalcAll(
        mode: Int, dao: CourseColorDao, gids: [String]
    ) async -> Int {
        if mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC { return 0 }
        let anchor = resolveAnchor(mode: mode)
        if anchor == nil { return 0 }
        return recalcWithAnchor(anchor: anchor, dao: dao, gids: gids).count
    }

    static func recalcAll(
        dao: CourseColorDao, gids: [String], prefs: AppPrefs = .shared
    ) -> Int {
        let mode = prefs.getCourseColorMode()
        guard mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC else { return 0 }
        return recalcWithAnchor(anchor: resolveAnchor(mode: mode, prefs: prefs), dao: dao, gids: gids).count
    }

    /// 当前深浅档主题 primary 的 anchor 解析 — 与 SwiftUI 渲染路径同一派生函数。
    ///   system → iOS 语义色 (Material You 动态取色在 iOS 不可达);
    ///   custom:<id> → CustomSchemeDeriver.derive(...) 同一函数;
    ///   其他 → ThemePresets.byKey 取深浅 primary。
    static func resolveAnchor(mode: Int, prefs: AppPrefs = .shared) -> Float? {
        guard let primaryColor = currentThemePrimaryColor(prefs: prefs) else { return nil }
        let argb = colorToArgb(primaryColor)
        let seedHue = prefs.getCourseColorSeedHue()
        return CourseColorUtil.resolveAnchor(mode: mode, themePrimaryArgb: argb, seedHue: seedHue)
    }

    /// 解析当前主题(primary)颜色。
    /// 跟 Android themePrimaryArgb(Context) 对齐: system→系统语义色兜底品牌紫,
    /// custom:<id>→CustomSchemeDeriver.derive 同一派生; 其他→ThemePresets 当前深浅 primary。
    private static func currentThemePrimaryColor(prefs: AppPrefs) -> Color? {
        let themeKey = prefs.getThemeKey()
        let isDark = prefs.isDarkMode()
        if themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
            let id = String(themeKey.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
            let seed = CustomThemeStore.getById(id) ?? defaultSeedTheme()
            return CustomSchemeDeriver.derive(theme: seed, isDark: isDark).primary
        } else if themeKey == ThemePresets.KEY_SYSTEM {
            // iOS 無 Material You 動態取色 → 回退預設套品牌紫 (0xFF6750A4)
            let preset = ThemePresets.byKey(ThemePresets.KEY_DEFAULT)
            return isDark ? preset.dark.primary : preset.light.primary
        } else {
            let preset = ThemePresets.byKey(themeKey)
            return isDark ? preset.dark.primary : preset.light.primary
        }
    }

    /// custom:<id> id 读不到(已删)时回落种子 = 默认淡紫 (← Android Theme.kt)。
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
