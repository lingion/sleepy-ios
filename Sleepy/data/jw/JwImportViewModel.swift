// JwImportViewModel.swift — ← JwImportViewModel.kt
// 教务直连导入 ViewModel
//
// 职责:
//  1. 加载 schools.json 学校列表
//  2. 用户选定学校 + 协议后,通过 WebView 抓 HTML 源码(屏幕层 JwWebViewLoginScreen 负责)
//  3. 用对应协议 parser 解析 HTML → [JwCourse]
//  4. 转 CourseEntity 列表,落库
//
// 简化点(相对 wakeup 原版 ImportViewModel):
//  - 不在 ViewModel 内做 HTTP 抓取(WebView 内完成)
//  - 不在 ViewModel 内做登录流程(用户输账号密码 + 验证码)
//  - 特殊学校(清华/吉大/华科等)v1.0.8 不支持
//
// AndroidViewModel+StateFlow → ObservableObject+@Published(async 任务在 Task 里发)。

import Foundation
import GRDB

final class JwImportViewModel: ObservableObject {

    @Published private(set) var schools: [JwSchoolInfo] = []
    @Published private(set) var importState: ImportState = .idle

    init() {
        loadSchools()
    }

    private func loadSchools() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let url = Bundle.main.url(forResource: "schools", withExtension: "json") else {
                    throw NSError(domain: "JwImport", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "schools.json missing"])
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                let list = Self.parseSchoolsJson(text)
                DispatchQueue.main.async {
                    self?.schools = list
                }
            } catch {
                DispatchQueue.main.async {
                    self?.importState = .error("加载学校列表失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func parseSchoolsJson(_ text: String) -> [JwSchoolInfo] {
        guard let data = text.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var list: [JwSchoolInfo] = []
        list.reserveCapacity(arr.count)
        for obj in arr {
            let aliases = (obj["aliases"] as? [String]) ?? []
            let typeStr = (obj["type"] as? String) ?? ""
            list.append(JwSchoolInfo(
                sortKey: obj["sortKey"] as? String ?? "",
                name: obj["name"] as? String ?? "",
                url: obj["url"] as? String ?? "",
                type: typeStr.isEmpty ? nil : typeStr,
                aliases: aliases,
                sortKeyFull: obj["sortKeyFull"] as? String ?? ""
            ))
        }
        return list
    }

    /// 解析 HTML 源码,返回课程列表(不入库) ← suspend parseHtml
    static func parseHtml(_ html: String, protocolType: String) throws -> [JwCourse] {
        if protocolType.trimmingCharacters(in: .whitespaces).isEmpty {
            // 未知协议(URL 直接登录):尝试所有 parser,取课程数最多的结果
            return tryAllParsers(html)
        }
        let parser: JwParser
        switch protocolType {
        case JwProtocol.TYPE_QZ: parser = JwQzParser(html)
        case JwProtocol.TYPE_QZ_CRAZY: parser = JwQzCrazyParser(html)
        case JwProtocol.TYPE_QZ_BR: parser = JwQzParser(html)
        case JwProtocol.TYPE_QZ_WITH_NODE: parser = JwQzParser(html)
        case JwProtocol.TYPE_QZ_OLD: parser = JwQzParser(html)
        case JwProtocol.TYPE_URP: parser = JwUrpParser(html)
        case JwProtocol.TYPE_URP_NEW: parser = JwNewUrpParser(html)
        case JwProtocol.TYPE_WISEDU: parser = JwWiseduParser(html)
        case JwProtocol.TYPE_ZF: parser = JwNewZfParser(html)
        case JwProtocol.TYPE_ZF_NEW: parser = JwNewZfParser(html)
        case JwProtocol.TYPE_ZF_1: parser = JwNewZfParser(html)
        default:
            throw NSError(domain: "JwImport", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "协议 \(protocolType) 暂不支持"])
        }
        return parser.generateCourseList()
    }

    /// 未知协议时,尝试所有 parser,取课程数最多的结果
    private static func tryAllParsers(_ html: String) -> [JwCourse] {
        let candidates: [JwParser] = [
            JwWiseduParser(html),
            JwNewUrpParser(html),
            JwNewZfParser(html),
            JwQzParser(html),
            JwQzCrazyParser(html),
            JwUrpParser(html)
        ]
        var best: [JwCourse] = []
        for p in candidates {
            let result = p.generateCourseList()  // ← Kotlin 逐个 try/catch continue;Swift 解析器内部已全吞异常
            if result.count > best.count { best = result }
        }
        return best
    }

    /// 从 URL 自动检测教务协议类型 ← detectProtocolFromUrl
    static func detectProtocolFromUrl(_ url: String) -> String? {
        let u = url.lowercased()
        if u.contains("jwapp/sys/") || u.contains("/jwapp/") { return JwProtocol.TYPE_WISEDU }
        if u.contains("jwglxt") || u.contains("/xtgl/") { return JwProtocol.TYPE_ZF_NEW }
        if u.contains("/jwtottxuxsysb/") { return JwProtocol.TYPE_ZF_NEW }
        if u.contains("qz") || u.contains("strongdesk") { return JwProtocol.TYPE_QZ }
        if u.contains("urp") { return JwProtocol.TYPE_URP_NEW }
        return nil
    }

    /// 把 JwCourse 列表转成 sleepy 的 CourseEntity 列表 ← toCourseEntities
    static func toCourseEntities(_ courses: [JwCourse], tableId: Int64, defaultColor: String) -> [CourseEntity] {
        return courses.map { jw in
            let step = max(jw.endNode - jw.startNode + 1, 1)
            return CourseEntity(
                groupId: "",
                tableId: tableId,
                courseName: jw.name.isEmpty ? "未命名" : jw.name,
                teacher: jw.teacher,
                room: jw.room,
                day: min(max(jw.day, 1), 7),
                startNode: max(jw.startNode, 1),
                step: step,
                startWeek: max(jw.startWeek, 1),
                endWeek: max(jw.endWeek, jw.startWeek),
                type: jw.type,
                color: defaultColor,
                id: 0
            )
        }
    }

    /// 创建新课表并落库。返回新 tableId。 ← suspend importAsNewTable
    static func importAsNewTable(
        _ db: AppDatabase,
        courses: [JwCourse],
        tableName: String,
        startDate: String? = nil,
        timeJson: String = "",
        nodesPerDay: Int = 0
    ) throws -> Int64 {
        if courses.isEmpty {
            throw NSError(domain: "JwImport", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "课程列表为空,请确认已到达课表页面"])
        }

        // ★ 整个建表 + 落库包在单一事务里:中途失败回滚,避免留下空课表。 ← db.withTransaction
        return try db.dbQueue.write { dbw in
            let tableDao = db.timeTableDao
            let courseDao = db.courseDao

            // ★ 用 autoGenerate (id=0) 让 GRDB 分配真实主键,避免手动 max(id)+1 撞旧 ID 覆盖既有课表。
            let resolvedStartDate = (startDate?.isEmpty == false ? startDate : nil)
                ?? computeCurrentSemesterStart()
            let maxNode = nodesPerDay > 0 ? nodesPerDay : courses.map { max($0.startNode, $0.endNode) }.max() ?? 1
            var newTable = TimeTableEntity(
                name: tableName.isEmpty ? "导入的课表" : tableName,
                startDate: resolvedStartDate,
                nodesPerDay: maxNode,
                timeJson: timeJson.isEmpty ? TimeTableUtils.DEFAULT_TIME_JSON : timeJson,
                isDefault: true,  // 导入的课表设为默认,widget 直接展示
                id: 0
            )
            let generatedId = try tableDao.insertInDb(dbw, newTable)
            // 把其他表设为非 default,确保只有当前表是 default
            try tableDao.setDefaultInDb(dbw, generatedId)

            // 落库课程
            let defaultColor = "#FF6750A4"
            // 按课程名分 groupId(同名课程视为一组,便于编辑)
            var nameToGroup: [String: String] = [:]
            var entities = toCourseEntities(courses, tableId: generatedId, defaultColor: defaultColor)
            for i in entities.indices {
                let gid: String
                if let g = nameToGroup[entities[i].courseName] {
                    gid = g
                } else {
                    gid = UUID().uuidString
                    nameToGroup[entities[i].courseName] = gid
                }
                entities[i].groupId = gid
            }
            try courseDao.insertAllInDb(dbw, entities)
            return generatedId
        }
    }

    /// 默认学期开始日期:本学期第一周周一的 ISO 日期。
    /// 如果当前是寒暑假(2月/8月),回退到上一学期。 ← computeCurrentSemesterStart
    private static func computeCurrentSemesterStart() -> String {
        let today = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!  // LocalDate.now() 系统默认时区,App 主要使用场景
        let month = cal.component(.month, from: today)
        let year = cal.component(.year, from: today)
        let semesterStartYear = (8...12).contains(month) ? year : year - 1
        let semesterStartMonth = (8...12).contains(month) ? 9 : 2
        var comps = DateComponents()
        comps.year = semesterStartYear
        comps.month = semesterStartMonth
        comps.day = 1
        // ← firstDay.with(TemporalAdjusters.firstInMonth(DayOfWeek.MONDAY))
        var firstDay = cal.date(from: comps)!
        let weekday = cal.component(.weekday, from: firstDay)  // 1=Sun..7=Sat
        let offset = weekday == 2 ? 0 : (weekday == 1 ? 1 : 9 - weekday)
        firstDay = cal.date(byAdding: .day, value: offset, to: firstDay)!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: firstDay)
    }

    // ← sealed class ImportState
    enum ImportState {
        case idle
        case parsed([JwCourse])
        case imported(Int64)
        case error(String)
    }
}
