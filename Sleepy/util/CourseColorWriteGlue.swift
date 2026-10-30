// CourseColorWriteGlue.swift — ← util/CourseColorWriteGlue.kt (v1.0.62, GPL-3.0)
// 派生档写侧胶水 — spec §2.4「新课按当前模式算 hue 写表」。
//
// 渲染层保持纯读(persistedHue ?: stableHue); course_colors 写入只发生在
// 课程组**诞生**时刻: 教务导入 / 文件导入 / 覆盖导入 / 单课新增。
//
// 红线(spec §2.1/§2.3):
//   - CLASSIC 档(anchor=nil)绝不写表 — 升级零变化, course_colors 保持空;
//   - 钉死性: 既有组 hue 永不被本胶水移动, 只给「表中查无」的新组补色;
//   - 配色是增值数据: 读写异常一律吞掉降级为不写, 绝不影响课程落库主流程
//     (查无 hue → 渲染回落 stableHue 老路径, 主题重算/手动重排可自愈)。
//
// 平台差异(记录在案): Android KEY_SYSTEM 主题走 Material You 动态取色
// (dynamicLight/DarkColorScheme, 壁纸派生); iOS 无等价 API, 走
// SleepyThemeProvider.dynamicSystemScheme(dark:) 的固定语义色映射
// (primary = systemPurple) — 派生档 FOLLOW_THEME 在 system 主题下因此是
// 稳定色而非壁纸派生色, 其余行为与 Android 一致。

import Foundation
import UIKit
import SwiftUI
import GRDB

enum CourseColorWriteGlue {

    // MARK: - 新组补色

    /// 为 entities 中的新组补持久 hue(既有组只读跳过); 返回本次写入的 gid→hue。
    @discardableResult
    static func persistNewGroupHues(dao: CourseColorDao,
                                    entities: [CourseEntity],
                                    prefs: AppPrefs = .shared) -> [String: Float] {
        // 配色是增值数据 — 全程吞异常降级为不写
        do {
            let mode = prefs.getCourseColorMode()
            if mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC { return [:] }
            guard let anchor = resolveAnchor(mode: mode, prefs: prefs) else { return [:] }
            let tableKey = CourseColorEntity.globalTableKey
            let persisted = (try? dao.getHueMap(tableKey)) ?? [:]
            let plan = planNewGroups(anchor: anchor,
                                     persisted: persisted,
                                     entities: entities)
            if !plan.isEmpty {
                let rows = plan.map { CourseColorEntity(tableKey: tableKey, groupId: $0.key, hue: $0.value) }
                try dao.upsertAll(rows)
                CourseHueStore.shared.invalidate() // 渲染快照即时跟表
            }
            return plan
        } catch {
            return [:]
        }
    }

    /// 事务内版本 — ← Android JwImportViewModel 内「同一 Room 事务内补色」。
    /// iOS GRDB 的 db.write 重入会死锁, 故调用方持事务句柄时必须走此入口。
    @discardableResult
    static func persistNewGroupHuesInDb(dbw: Database,
                                        dao: CourseColorDao,
                                        entities: [CourseEntity],
                                        prefs: AppPrefs = .shared) -> [String: Float] {
        do {
            let mode = prefs.getCourseColorMode()
            if mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC { return [:] }
            guard let anchor = resolveAnchor(mode: mode, prefs: prefs) else { return [:] }
            let tableKey = CourseColorEntity.globalTableKey
            let persisted = (try? dao.getHueMapInDb(dbw, tableKey)) ?? [:]
            let plan = planNewGroups(anchor: anchor,
                                     persisted: persisted,
                                     entities: entities)
            if !plan.isEmpty {
                let rows = plan.map { CourseColorEntity(tableKey: tableKey, groupId: $0.key, hue: $0.value) }
                try dao.upsertAllInDb(dbw, rows)
                CourseHueStore.shared.invalidate()
            }
            return plan
        } catch {
            return [:]
        }
    }

    /// 新组筛选 + 编排 — Android persistNewGroupHues 的核心两行:
    ///   newGids = entities.map{groupId}.filter{ isNotBlank && !in persisted }.distinct()
    ///   plan    = planHuesForGroups(anchor, persisted.values, newGids)
    private static func planNewGroups(anchor: Float,
                                      persisted: [String: Float],
                                      entities: [CourseEntity]) -> [String: Float] {
        var seen = Set<String>()
        var newGids: [String] = []
        for e in entities {
            let gid = e.groupId.trimmingCharacters(in: .whitespacesAndNewlines)
            if gid.isEmpty || persisted[gid] != nil { continue }
            if seen.contains(gid) { continue }
            seen.insert(gid)
            newGids.append(gid)
        }
        if newGids.isEmpty { return [:] }
        return CourseColorUtil.planHuesForGroups(anchor: anchor,
                                                 existingHues: Array(persisted.values),
                                                 gids: newGids)
    }

    // MARK: - 全表重算

    /// 以 anchor 对全部非空白、去重 groupId 重新编排 hue 并 REPLACE 落库。
    /// 语义钉死:
    ///   - anchor=nil(CLASSIC 或解析失败) → 零写 — 表不动, 渲染走 stableHue;
    ///   - 换 anchor 重排**所有**组(「换主题重排课表整体颜色」= 用户批准的目标行为),
    ///     与 persistNewGroupHues 的「钉死既有组」相反 — 那是导入路, 这是重算路;
    ///   - 顺序 = 调用方传入序(上层显式排序保确定性);
    ///   - 异常吞掉返回已写部分。
    @discardableResult
    static func recalcWithAnchor(anchor: Float?, dao: CourseColorDao, gids: [String]) -> [String: Float] {
        do {
            var seen = Set<String>()
            var distinct: [String] = []
            for g in gids {
                let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || seen.contains(t) { continue }
                seen.insert(t)
                distinct.append(t)
            }
            let plan = CourseColorUtil.planHuesForGroups(anchor: anchor,
                                                          existingHues: [],
                                                          gids: distinct)
            if !plan.isEmpty {
                let rows = plan.map {
                    CourseColorEntity(tableKey: CourseColorEntity.globalTableKey,
                                      groupId: $0.key, hue: $0.value)
                }
                try dao.upsertAll(rows)
                CourseHueStore.shared.invalidate()
            }
            return plan
        } catch {
            return [:]
        }
    }

    /// App 级重算入口(AppearanceScreen/主题挂钩调用)。返回重算组数。
    @discardableResult
    static func recalcAll(dao: CourseColorDao, gids: [String], prefs: AppPrefs = .shared) -> Int {
        let mode = prefs.getCourseColorMode()
        if mode == AppPrefs.COURSE_COLOR_MODE_CLASSIC { return 0 }
        guard let anchor = resolveAnchor(mode: mode, prefs: prefs) else { return 0 }
        return recalcWithAnchor(anchor: anchor, dao: dao, gids: gids).count
    }

    // MARK: - anchor 解析

    /// 当前深浅档主题 primary 的 anchor 解析 — 与渲染路径同一派生函数(spec §2.2 契约4)。
    static func resolveAnchor(mode: Int, prefs: AppPrefs = .shared) -> Float? {
        guard let argb = themePrimaryArgb(prefs: prefs) else { return nil }
        return CourseColorUtil.resolveAnchor(mode: mode,
                                             themePrimaryArgb: argb,
                                             seedHue: prefs.getCourseColorSeedHue())
    }

    /// 主题 primary → ARGB。解析规则逐条对齐 App 端 SleepyThemeProvider:
    /// custom:&lt;id&gt; → CustomSchemeDeriver 同一函数(已删 id 回落默认淡紫);
    /// system → dynamicSystemScheme(平台差异,见文件头说明);
    /// 其余预设 → ThemePresets.byKey(key).light/.dark.primary。
    static func themePrimaryArgb(prefs: AppPrefs = .shared) -> Int? {
        let key = prefs.getThemeKey()
        let dark = prefs.isDarkMode(isSystemDark: currentSystemDark())
        let primary: Color
        if key == ThemePresets.KEY_SYSTEM {
            primary = SleepyThemeProvider.dynamicSystemScheme(dark: dark).primary
        } else if key.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
            let id = String(key.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
            let seed = CustomThemeStore.getById(id) ?? SleepyThemeProvider.defaultSeedTheme
            primary = CustomSchemeDeriver.derive(theme: seed, isDark: dark).primary
        } else {
            let preset = ThemePresets.byKey(key)
            primary = dark ? preset.dark.primary : preset.light.primary
        }
        return toArgb(primary)
    }

    /// 手拼 ARGB — UIColor.getRed 取分量(不用 SwiftUI Color→CGColor, 跨版本不稳)。
    /// ★ 分量取整必须**截断**而非四舍五入 — Android CourseColorWriteGlue.toArgb 用
    ///   (c.red * 255).toInt() 截断; 四舍五入会使每通道偏差至多 1/255,
    ///   反算出的 anchor hue 与 Android 差至多约 0.4°(配色可觉察地不同)。
    static func toArgb(_ color: Color) -> Int? {
        #if os(watchOS)
        let ui = UIColor(color)
        #else
        let ui = UIColor(color)
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(max(0, min(255, r * 255)))       // 截断(Android toInt 语义)
        let gi = Int(max(0, min(255, g * 255)))
        let bi = Int(max(0, min(255, b * 255)))
        return (0xFF << 24) | (ri << 16) | (gi << 8) | bi
    }
}
