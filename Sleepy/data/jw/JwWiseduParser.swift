// JwWiseduParser.swift — ← JwWiseduParser.kt
// 金智 Wisedu jwapp 教务平台课表 JSON 解析器。
//
// 适配学校:哈尔滨工程大学 (jwgl.hrbeu.edu.cn) 及其他金智微应用平台。
// 与其它 JwParser 子类不同:source 不是 HTML,而是课表 API 的 JSON 响应
// (在 WebView 内通过 fetch 拿到,见 JwWebViewLoginScreen 的 wisedu 分支)。
//
// 数据来源:POST /jwapp/sys/wdkb/modules/xskcb/xskcb.do  (body: XNXQDM=学年学期)
// 返回结构:{"code":"0","datas":{"xskcb":{"rows":[{...}]}}}
//
// 字段映射(教务 → JwCourse):
//   KCM   课程名      → name
//   SKJS  上课教师    → teacher
//   JASMC 教室名称    → room
//   SKXQ  星期(1=周一..7=周日) → day
//   KSJC  开始节次    → startNode
//   JSJC  结束节次    → endNode
//   SKZC  周次 bitmap → startWeek/endWeek/type(SKZC 第 i 位(0-indexed)='1' 表示第 (i+1) 周上课)
//
// 一门课多时段 = 多行(按行展开);不连续周次 = 拆成多个连续段,每段一个 JwCourse。
// 整体等差 step=2 的周次(如 11,13,15,17)压缩成单周/双周(type=1/2)。
// (kotlinx-serialization 宽松 JSON → JSONSerialization,语义等价)
//
// open for WHUT: 武汉理工同属金智 jwapp 但走 kcbcxby 微应用 (cxxskcb 路径) 且
// 节次 DM 需映射 — 子类 JwWhutParser 注入 rows 路径别名与节次映射。

import Foundation

class JwWiseduParser: JwParser, JwParserConfidenceReporting {

    let source: String

    required init(_ source: String) {
        self.source = source
    }

    /// rows 所在路径 datas.<module>.rows; 子类可注入别名 (WHUT = xskcb + cxxskcb)。
    var moduleNames: [String] { ["xskcb"] }

    /// 节次 DM → 物理节次; 默认直通 (HEU DM 即物理节次)。
    func mapSection(_ dm: Int) -> Int { dm }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []  // ← kotlinx Json 宽松解析失败 → 空(Kotlin 侧异常由调用方 catch)
        }
        let datas = root["datas"] as? [String: Any]
        // ← firstNotNullOfOrNull { datas[it]?.jsonObject }: key 缺失 → `?.` 短路试下一个模块名;
        //   存在但不是对象 (JSON null/数组/标量) → Kotlin `.jsonObject` 抛
        //   IllegalArgumentException, iOS 同形抛 JwParseError (对齐 JwNewUrpParser:178),
        //   不再静默当成"没有该模块"。
        var module: [String: Any]?
        if let d = datas {
            for name in moduleNames {
                guard let v = d[name] else { continue }
                guard let m = v as? [String: Any] else {
                    throw JwParseError(message: "JwWiseduParser: datas.\(name) is not a JSON object")
                }
                module = m
                break
            }
        }
        let rows = module?["rows"] as? [[String: Any]] ?? []

        var result: [JwCourse] = []
        for o in rows {
            // kotlinx `jsonPrimitive.contentOrNull`: JSON 数字 (NSNumber) 也取其字面文本
            // ("SKXQ": 1 → "1"), 与 JwChaoxingParser/JwQzAppParser 同款 NSNumber 容错读。
            // 只认 `as? String` 会令数字型 SKXQ/KSJC/JSJC 整行丢失 (v1.0.61 对齐修复)。
            func str(_ k: String) -> String {
                (((o[k] as? String) ?? (o[k] as? NSNumber)?.stringValue) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            func int(_ k: String) -> Int? { Int(str(k)) }

            let name = str("KCM")
            if name.isEmpty { continue }  // ← isBlank
            let teacher = str("SKJS")
            let room = str("JASMC")
            guard let day = int("SKXQ") else { continue }
            guard let rawStartNode = int("KSJC") else { continue }
            let startNode = mapSection(rawStartNode)
            let endNode = int("JSJC").map { mapSection($0) } ?? startNode
            let skzc = str("SKZC")

            for (sw, ew, type) in weekRuns(skzc) {
                result.append(JwCourse(
                    name: name,
                    room: room,
                    teacher: teacher,
                    day: min(max(day, 1), 7),                    // ← coerceIn(1,7)
                    startNode: max(startNode, 1),                // ← coerceAtLeast(1)
                    endNode: max(endNode, startNode),            // ← coerceAtLeast(startNode)
                    startWeek: sw,
                    endWeek: ew,
                    type: type
                ))
            }
        }
        return result
    }

    /// SKZC 周次 bitmap → 连续段列表 [(startWeek, endWeek, type)]。
    /// type: 0=每周(连续段), 1=单周, 2=双周。
    ///
    /// - 单个连续段 → type=0。
    /// - 整体等差 step=2(全奇或全偶)→ 压缩成单周(1)/双周(2)。
    /// - 其余(多段非等差)→ 拆成多个连续段,每段 type=0。
    ///
    /// 此逻辑已用哈工程真实数据校验:解析周次集合与教务 ZCMC 100% 一致、无损还原。
    private func weekRuns(_ skzc: String) -> [(Int, Int, Int)] {
        // ← mapIndexedNotNull { i, c -> if (c == '1') i + 1 else null }
        let weeks = skzc.enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
        if weeks.isEmpty { return [] }

        // 拆连续段
        var runs: [(Int, Int)] = []
        var start = weeks[0]
        var prev = weeks[0]
        for w in weeks.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                runs.append((start, prev))
                start = w
                prev = w
            }
        }
        runs.append((start, prev))

        if runs.count == 1 {
            return [(runs[0].0, runs[0].1, 0)]
        }
        // 整体单/双周(等差 step=2)
        if weeks.count >= 2 && (1..<weeks.count).allSatisfy({ weeks[$0] - weeks[$0 - 1] == 2 }) {
            let type = weeks.first! % 2 == 1 ? 1 : 2
            return [(weeks.first!, weeks.last!, type)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }

    /// T8: /jwapp/sys/wdkb/ = 100; xskcb.do = 90; datas.xskcb = 80
    var confidenceValue: Int {
        if source.contains("/jwapp/sys/wdkb/") { return 100 }
        if source.contains("xskcb.do") { return 90 }
        if source.contains("datas.xskcb") { return 80 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("/jwapp/sys/wdkb/") { out.append("jwapp/sys/wdkb") }
        if source.contains("xskcb.do") { out.append("xskcb.do") }
        if source.contains("datas.xskcb") { out.append("datas.xskcb.rows") }
        return out
    }
}
