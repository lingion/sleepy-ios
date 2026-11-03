// JwParserRegistry.swift — ← JwParserRegistry.kt + JwParser.kt (confidence/nameForDiag 部分)
//
// T8 — 统一解析分发与兜底裁决。
//
// 单一来源：协议 type → parser 工厂；type 为空时跑全部候选按 confidence/课程数裁决。
// ParserAttempt 快照供 T9 诊断（JwParseDiagnostics.classify）消费。

import Foundation

/// T8 新增：基于 HTML 结构锚点的命中置信度（0..100）。
/// 默认 0；有 confidence 的 parser 由各自类型实现 protocolConfidence()。
/// confidence 不调 generateCourseList（避免 N+1），只看 HTML 静态特征。
extension JwParser {
    var protocolConfidence: Int { (self as? JwParserConfidenceReporting)?.confidenceValue ?? 0 }
    var protocolMatchedFeatures: [String] { (self as? JwParserConfidenceReporting)?.matchedFeatureList ?? [] }
}

/// 有锚点置信度报告能力的 parser(对应 Kotlin open fun confidence()/matchedFeatures() 覆写)
protocol JwParserConfidenceReporting {
    var confidenceValue: Int { get }
    var matchedFeatureList: [String] { get }
}

/// 诊断用异常，带每个 parser 的尝试快照。
///
/// T9 通过 catch JwParseError 拿到 attempts 列表喂给 JwParseDiagnostics.classify。
struct JwParseError: Error {
    let message: String
    var attempts: [ParserAttemptSnapshot] = []

    /// T8: 缺表等已分类异常的语义标记(JwQzParser 找不到 #kbtable 时)
    static let NO_TABLE_CONTAINER_MARKER = "NO_TABLE_CONTAINER_MARKER"
}

/// Registry 侧 attempt 快照(Kotlin JwParserRegistry.ParserAttempt 1:1)
struct ParserAttemptSnapshot: Equatable {
    var parserName: String        // e.g. "JwOldZfParser(type=0)"
    var type: String?             // JwProtocol.TYPE_* 或 nil(兜底时未声明)
    var courseCount: Int
    var confidence: Int
    var matchedFeatures: [String]
    var exception: String?        // 简短异常类名+message，禁止含 HTML 全文

    /// ← JwParseDiagnostics.ParserAttempt 转换(Kotlin 里 T9 直接复用 data class)
    var asDiag: JwParseDiagnostics.ParserAttempt {
        JwParseDiagnostics.ParserAttempt(parserName: parserName, courseCount: courseCount, exception: exception)
    }
}

enum JwParserRegistry {

    /// 协议族优先级表。数字越小优先级越高（用于并列裁决）。
    /// 优先级反映"误抢风险"：协议族特征越窄、越独特，越优先。
    static let TYPE_PRIORITY: [(String, Int)] = [
        (JwProtocol.TYPE_KINGO_NEW, 8),
        (JwProtocol.TYPE_JZ, 9),
        (JwProtocol.TYPE_SOUTH_SOFT, 10),
        (JwProtocol.TYPE_CHAOXING_LEGACY, 11),
        (JwProtocol.TYPE_SHUWEI, 12),
        (JwProtocol.TYPE_SUDA_POST, 13),
        (JwProtocol.TYPE_CUMTB, 14),
        (JwProtocol.TYPE_XJU_POST, 15),
        (JwProtocol.TYPE_THU, 16),
        (JwProtocol.TYPE_UMOOC, 13),
        (JwProtocol.TYPE_YL, 13),
        (JwProtocol.TYPE_ECUPL, 16),
        (JwProtocol.TYPE_ECUPL_SCRIPT, 17),
        (JwProtocol.TYPE_ECUPL_SUPER, 18),
        (JwProtocol.TYPE_NEW_URP_SUPER, 16),
        (JwProtocol.TYPE_NWPU_POST, 16),
        (JwProtocol.TYPE_KINGO_ZX, 205),
        (JwProtocol.TYPE_SCAU, 200),
        (JwProtocol.TYPE_WISEDU, 20),
        (JwProtocol.TYPE_CQU, 25),
        (JwProtocol.TYPE_CHAOXING, 26),
        (JwProtocol.TYPE_BOYA_PP, 27),
        (JwProtocol.TYPE_EAMS5, 28),
        (JwProtocol.TYPE_CLASSIC_EAMS, 29),
        (JwProtocol.TYPE_NUIT, 30),
        (JwProtocol.TYPE_KUST, 31),
        (JwProtocol.TYPE_PKU, 32),
        (JwProtocol.TYPE_SEU, 33),
        (JwProtocol.TYPE_ZJU, 34),
        (JwProtocol.TYPE_USTC, 35),
        (JwProtocol.TYPE_SCU, 36),
        (JwProtocol.TYPE_NEU, 37),
        (JwProtocol.TYPE_BJTU, 38),
        (JwProtocol.TYPE_YETHAN, 39),
        (JwProtocol.TYPE_BNUZ, 40),
        (JwProtocol.TYPE_CF_NEW, 45),
        (JwProtocol.TYPE_CF, 50),
        (JwProtocol.TYPE_HNUST, 60),
        (JwProtocol.TYPE_HNIU, 65),
        (JwProtocol.TYPE_ZF, 70),
        (JwProtocol.TYPE_ZF_1, 75),
        (JwProtocol.TYPE_URP, 80),
        (JwProtocol.TYPE_URP_NEW, 85),
        (JwProtocol.TYPE_ZF_NEW, 90),
        (JwProtocol.TYPE_QZ, 100),
        (JwProtocol.TYPE_QZ_CRAZY, 110),
        (JwProtocol.TYPE_QZ_BR, 120),
        (JwProtocol.TYPE_QZ_WITH_NODE, 130),
        (JwProtocol.TYPE_QZ_IEAS, 140),
        (JwProtocol.TYPE_QZ_APP, 141),
        (JwProtocol.TYPE_UCAS, 142),
        (JwProtocol.TYPE_QZ_OLD, 145),
    ]

    /// 单一来源：协议 type → parser 工厂。
    /// 注意：TYPE_ZF_1 复用 JwOldZfParser(type=1)。
    static func factoryFor(_ type: String) -> ((String) -> JwParser)? {
        switch type {
        case JwProtocol.TYPE_WISEDU: return { JwWiseduParser($0) }
        case JwProtocol.TYPE_WHUT: return { JwWhutParser($0) }
        case JwProtocol.TYPE_CQU: return { JwCquParser($0) }
        case JwProtocol.TYPE_CHAOXING: return { JwChaoxingParser($0) }
        case JwProtocol.TYPE_BOYA_PP: return { JwBoyaPpParser($0) }
        case JwProtocol.TYPE_EAMS5: return { JwEams5Parser($0) }
        case JwProtocol.TYPE_CLASSIC_EAMS: return { JwClassicEamsParser($0) }
        case JwProtocol.TYPE_SEU: return { JwSeuParser($0) }
        case JwProtocol.TYPE_ZJU: return { JwZjuParser($0) }
        case JwProtocol.TYPE_USTC: return { JwUstcParser($0) }
        case JwProtocol.TYPE_SCU: return { JwScuParser($0) }
        case JwProtocol.TYPE_NEU: return { JwNeuParser($0) }
        case JwProtocol.TYPE_BJTU: return { JwBjtuParser($0) }
        case JwProtocol.TYPE_URP_NEW: return { JwNewUrpParser($0) }
        case JwProtocol.TYPE_ZF_NEW: return { JwNewZfParser($0) }
        case JwProtocol.TYPE_ZF: return { JwOldZfParser($0, oldType: 0) }
        case JwProtocol.TYPE_ZF_1: return { JwOldZfParser($0, oldType: 1) }
        case JwProtocol.TYPE_URP: return { JwUrpParser($0) }
        case JwProtocol.TYPE_QZ: return { JwQzParser($0) }
        case JwProtocol.TYPE_QZ_CRAZY: return { JwQzCrazyParser($0) }
        case JwProtocol.TYPE_QZ_BR: return { JwQzBrParser($0) }
        case JwProtocol.TYPE_QZ_WITH_NODE: return { JwQzWithNodeParser($0) }
        case JwProtocol.TYPE_QZ_OLD: return { JwOldQzParser($0) }
        case JwProtocol.TYPE_QZ_APP: return { JwQzAppParser($0) }
        case JwProtocol.TYPE_QZ_IEAS: return { JwQzIeasParser($0) }
        case JwProtocol.TYPE_UCAS: return { JwUcasParser($0) }
        case JwProtocol.TYPE_CF: return { JwChengFangParser($0) }
        case JwProtocol.TYPE_PKU: return { JwPekingParser($0) }
        case JwProtocol.TYPE_BNUZ: return { JwBnuzParser($0) }
        case JwProtocol.TYPE_HNUST: return { JwHnustParser($0) }
        case JwProtocol.TYPE_HNIU: return { JwHniuParser($0) }
        case JwProtocol.TYPE_KINGO_NEW: return { JwKingoParser($0) }
        case JwProtocol.TYPE_KINGO_ZX: return { JwKingoZxParser($0) }
        case JwProtocol.TYPE_JZ: return { JwJzParser($0) }
        case JwProtocol.TYPE_SOUTH_SOFT: return { JwSouthSoftParser($0) }
        case JwProtocol.TYPE_CHAOXING_LEGACY: return { JwChaoxingLegacyParser($0) }
        case JwProtocol.TYPE_SHUWEI: return { JwShuweiParser($0) }
        case JwProtocol.TYPE_SUDA_POST: return { JwSudaParser($0) }
        case JwProtocol.TYPE_CUMTB: return { JwCumtbParser($0) }
        case JwProtocol.TYPE_XJU_POST: return { JwXjuParser($0) }
        case JwProtocol.TYPE_NEW_URP_SUPER: return { JwNewUrpSuperParser($0) }
        case JwProtocol.TYPE_THU: return { JwThuparser($0) }
        case JwProtocol.TYPE_NWPU_POST: return { JwNwpuPostParser($0) }
        case JwProtocol.TYPE_UMOOC: return { JwUmoocParser($0) }
        case JwProtocol.TYPE_YL: return { JwYlParser($0) }
        case JwProtocol.TYPE_ECUPL: return { JwEcuplParser($0) }
        case JwProtocol.TYPE_ECUPL_SCRIPT: return { JwEcuplScriptParser($0) }
        case JwProtocol.TYPE_ECUPL_SUPER: return { JwEcuplSuperParser($0) }
        case JwProtocol.TYPE_SCAU: return { JwScauParser($0) }
        case JwProtocol.TYPE_KUST: return { JwKustParser($0) }
        case JwProtocol.TYPE_NUIT: return { JwNuitParser($0) }
        case JwProtocol.TYPE_YETHAN: return { JwYethanParser($0) }
        case JwProtocol.TYPE_CF_NEW: return { JwCfNewParser($0) }
        default: return nil
        }
    }

    /// 静态候选（兜底用）：返回全部 parser 工厂列表，按 TYPE_PRIORITY 升序
    static func allCandidates(_ html: String) -> [(String?, JwParser)] {
        var out: [(String?, JwParser)] = []
        for entry in TYPE_PRIORITY {
            guard let f = factoryFor(entry.0) else { continue }
            out.append((entry.0, f(html)))
        }
        return out
    }

    /// 显式分发：type 已知时按工厂表单派。
    /// 未在表内的 type → 抛 JwParseError(等价 Kotlin IllegalArgumentException 语义,消息同形)。
    static func parserFor(_ type: String, _ html: String) throws -> JwParser {
        guard let f = factoryFor(type) else {
            throw JwParseError(message: "协议 \(type) 暂不支持")
        }
        return f(html)
    }

    /// schools.json type 能否被 Registry 路由(SchoolsJsonConsistencyTest 用)
    static func isRoutable(_ type: String) -> Bool {
        factoryFor(type) != nil
    }

    /// ← 原版本 JwParserRegistry.supports(type): 该 type 是否有已注册的 parser。
    /// 与 isRoutable 同义但接受可空 type(nil = 未声明协议 → 不支持),
    /// 供 JwSchoolInfo.canImport 的「未验证条目」判定使用。
    static func supports(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return false }
        return factoryFor(type) != nil
    }

    private struct Row {
        let type: String?
        let attempt: ParserAttemptSnapshot
        let result: [JwCourse]
    }

    /// 兜底：type 为空时跑全部候选，按 confidence 裁决。
    /// 返回 (best, attempts) — best 是 [JwCourse]，attempts 给 T9 诊断用。
    ///
    /// 性能注意：所有 parser 都会被实例化并 generateCourseList 一次（含 0 课情形）。
    /// 单测应控制 fixture 大小（< 50KB）以保持测试快速。
    static func selectBest(_ html: String, declaredType: String? = nil) -> ([JwCourse], [ParserAttemptSnapshot]) {
        var attempts: [ParserAttemptSnapshot] = []
        let candidates = allCandidates(html)

        var results: [Row] = []
        for (type, parser) in candidates {
            let conf = parser.protocolConfidence
            let matched = parser.protocolMatchedFeatures
            let count: Int
            let result: [JwCourse]
            let exMsg: String?
            do {
                let r = try parser.generateCourseList()
                count = r.count
                result = r
                exMsg = nil
            } catch let e as JwParseError {
                // 缺表等已分类异常: 保留首个 attempt 的语义标记 (NO_TABLE_CONTAINER_MARKER 等)
                count = 0
                result = []
                exMsg = e.attempts.first?.exception ?? JwParseError.NO_TABLE_CONTAINER_MARKER
            } catch {
                count = 0
                result = []
                exMsg = "\(Swift.type(of: error)): \(error.localizedDescription.prefix(60))"
            }
            let attempt = ParserAttemptSnapshot(
                parserName: nameForDiag(parser),
                type: type,
                courseCount: count,
                confidence: conf,
                matchedFeatures: matched,
                exception: exMsg)
            attempts.append(attempt)
            results.append(Row(type: type, attempt: attempt, result: result))
        }

        // 裁决规则（按优先级降序）：
        //   1. declaredType 已知且该 parser 解析出 >0 课 → 强制使用（用户选校信号 > 通用 confidence）
        //      declaredType 对应 parser 0 课 → 回退通用规则，不让"选错协议"变成永远 0 课死路
        //   2. 有 confidence >= 80 且 >0 课的候选 → 取 confidence 最高
        //   3. 其余 → courseCount 最大；并列时 confidence 高者先，再并列按 TYPE_PRIORITY 升序
        //   4. 全 0 课 → 空列表 + 全部 attempts
        let bestResult: [JwCourse]
        if let declaredType = declaredType, !declaredType.trimmingCharacters(in: .whitespaces).isEmpty {
            let declaredResult = results.first { $0.type == declaredType }?.result ?? []
            bestResult = declaredResult.isEmpty ? generalAdjudication(results) : declaredResult
        } else {
            bestResult = generalAdjudication(results)
        }

        return (bestResult, attempts)
    }

    /// 通用裁决（declaredType 为空，或 declaredType 对应 parser 0 课时的回退分支）
    private static func generalAdjudication(_ results: [Row]) -> [JwCourse] {
        let highConf = results.filter { $0.attempt.confidence >= 80 && !$0.result.isEmpty }
        if let best = highConf.max(by: { $0.attempt.confidence < $1.attempt.confidence }) {
            return best.result
        }
        let priorityOf: (String?) -> Int = { t in TYPE_PRIORITY.first { $0.0 == t }?.1 ?? 999 }
        let nonEmpty = results.filter { !$0.result.isEmpty }
        if nonEmpty.isEmpty { return [] }
        return nonEmpty.max { a, b in
            if a.result.count != b.result.count { return a.result.count < b.result.count }
            if a.attempt.confidence != b.attempt.confidence { return a.attempt.confidence < b.attempt.confidence }
            return priorityOf(a.type) > priorityOf(b.type)
        }?.result ?? []
    }

    /// T8 辅助：把 JwParser 名字格式化（含 JwOldZfParser.type=0/1、HNUST 的 oldQzType 等）
    static func nameForDiag(_ parser: JwParser) -> String {
        let cls = String(describing: Swift.type(of: parser))
        if let zf = parser as? JwOldZfParser { return "\(cls)(type=\(zf.oldType))" }
        if let hn = parser as? JwHnustParser { return "\(cls)(oldQzType=\(hn.oldQzType))" }
        return cls
    }
}
