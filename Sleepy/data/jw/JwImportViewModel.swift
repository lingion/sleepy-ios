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
    // ← v1.0.60 _schoolLocation StateFlow: 推荐卡定位状态机(8 态)
    @Published private(set) var schoolLocation: SchoolLocationState = .idle

    // internal: SchoolSelectScreen 的 launcher 等价接线需调 requestPermission(completion:)
    lazy var locator = SchoolCityLocator()
    private var locationJob: Task<Void, Never>? = nil

    init() {
        loadSchools()
    }

    /// ← locateSchoolCity(): 取消旧任务 → Locating → 启动定位
    func locateSchoolCity() {
        locationJob?.cancel()
        schoolLocation = .locating
        locationJob = Task { [weak self] in
            guard let self else { return }
            let result = await self.locator.locate()
            if Task.isCancelled { return }
            self.schoolLocation = result
        }
    }

    /// ← cancelSchoolLocation(): 取消任务; 仍在定位则回 Idle
    func cancelSchoolLocation() {
        locationJob?.cancel()
        locationJob = nil
        if case .locating = schoolLocation {
            schoolLocation = .idle
        }
    }

    private func loadSchools() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let url = Bundle.main.url(forResource: "schools", withExtension: "json") else {
                    throw NSError(domain: "JwImport", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "schools.json missing"])
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                // v1.0.60: 城市元数据与导入目录分离 — 解析失败绝不能阻止加载学校列表。
                var cityIndex: [String: [String]] = [:]
                if let cityUrl = Bundle.main.url(forResource: "school_cities", withExtension: "json"),
                   let cityText = try? String(contentsOf: cityUrl, encoding: .utf8) {
                    cityIndex = (try? SchoolCityIndex.parse(cityText)) ?? [:]
                }
                let list = Self.parseSchoolsJson(text).map { info -> JwSchoolInfo in
                    var v = info
                    v.cities = cityIndex[info.name] ?? []
                    return v
                }
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

    /// T12: 解析 schools.json 文本为学校列表。 ← parseSchoolsJson
    /// 跳过任何键以 "_" 开头的审计块（元数据不是学校条目）；
    /// status 字段缺失/未知回落 supported — 现有条目零行为变化。
    static func parseSchoolsJson(_ text: String) -> [JwSchoolInfo] {
        guard let data = text.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var list: [JwSchoolInfo] = []
        list.reserveCapacity(arr.count)
        for obj in arr {
            // T12: 审计块过滤 — 键名以 "_" 开头的对象是元数据
            if obj.keys.contains(where: { $0.hasPrefix("_") }) { continue }
            let aliases = (obj["aliases"] as? [String]) ?? []
            let typeStr = (obj["type"] as? String) ?? ""
            // ← kt:187 ifBlank { null } — 纯空白 type 同样视为未声明
            // status 字段缺失/未知回落 supported
            let rawStatus = (obj["status"] as? String) ?? ""
            let status: String
            switch rawStatus {
            case JwSchoolInfo.STATUS_PENDING: status = JwSchoolInfo.STATUS_PENDING
            case JwSchoolInfo.STATUS_LEGACY: status = JwSchoolInfo.STATUS_LEGACY
            case JwSchoolInfo.STATUS_GRAD_SUPPORTED: status = JwSchoolInfo.STATUS_GRAD_SUPPORTED
            case JwSchoolInfo.STATUS_GRAD_PENDING: status = JwSchoolInfo.STATUS_GRAD_PENDING
            default: status = JwSchoolInfo.STATUS_SUPPORTED
            }
            list.append(JwSchoolInfo(
                sortKey: obj["sortKey"] as? String ?? "",
                name: obj["name"] as? String ?? "",
                url: obj["url"] as? String ?? "",
                type: typeStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : typeStr,  // ← kt ifBlank
                status: status,
                aliases: aliases,
                sortKeyFull: obj["sortKeyFull"] as? String ?? "",
                enableFetch: (obj["enableFetch"] as? Bool) ?? false,
                cities: (obj["cities"] as? [String]) ?? []
            ))
        }
        return list
    }

    /// 解析 HTML 源码,返回课程列表(不入库) ← suspend parseHtml
    /// T8 重写: 分发表与候选都走 JwParserRegistry 单一工厂表。
    static func parseHtml(_ html: String, protocolType: String) throws -> [JwCourse] {
        try JwParseDispatch.parseOrThrow(html, protocolType)
    }

    /// T8: 显式分发的纯函数形式(不依赖 UIKit / GRDB)。 ← parseHtmlStatic
    /// 返回 (courses, attempts); 未知 type 包装 JwParseError 给 T9 分类。
    static func parseHtmlStatic(_ html: String, _ protocolType: String) throws -> (courses: [JwCourse], attempts: [ParserAttemptSnapshot]) {
        guard let parser = try? JwParserRegistry.parserFor(protocolType, html) else {
            // 已知 type 不在工厂表: 包装 JwParseError 给 T9 分类
            throw JwParseError(
                message: "协议 \(protocolType) 暂不支持",
                attempts: [ParserAttemptSnapshot(
                    parserName: "<none>",
                    type: protocolType,
                    courseCount: 0,
                    confidence: 0,
                    matchedFeatures: [],
                    exception: "JwParseError")])
        }
        do {
            let r = try parser.generateCourseList()
            return (r, [ParserAttemptSnapshot(
                parserName: JwParserRegistry.nameForDiag(parser),
                type: protocolType,
                courseCount: r.count,
                confidence: parser.protocolConfidence,
                matchedFeatures: parser.protocolMatchedFeatures,
                exception: nil)])
        } catch let e as JwParseError {
            throw e  // JwQzParser 找不到 #kbtable 的情况 — attempts 已带 NO_TABLE_CONTAINER_MARKER，直接冒泡
        } catch {
            throw JwParseError(
                message: "parser 解析异常: \(Swift.type(of: error)): \(error.localizedDescription.prefix(60))",
                attempts: [ParserAttemptSnapshot(
                    parserName: JwParserRegistry.nameForDiag(parser),
                    type: protocolType,
                    courseCount: 0,
                    confidence: parser.protocolConfidence,
                    matchedFeatures: parser.protocolMatchedFeatures,
                    exception: "\(Swift.type(of: error)): \(error.localizedDescription.prefix(60))")])
        }
    }

    /// 未知协议时,尝试所有 parser,按 confidence/课程数裁决 ← tryAllParsers(T8 起)
    static func tryAllParsers(_ html: String) -> [JwCourse] {
        JwParserRegistry.selectBest(html, declaredType: nil).0
    }

    /// 从 URL 自动检测教务协议类型（T6: 大小写归一 + 空值保护）← detectProtocolFromUrl
    /// ← kt:144 url.isBlank() — isBlank 含换行等全部 Unicode 空白
    static func detectProtocolFromUrl(_ url: String) -> String? {
        if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return detectProtocolFromUrlImpl(url.lowercased())
    }

    /// T6 新增：HTML 页面级协议识别（WebView 抓到的完整 HTML，已由 T7 合并 iframe/frame）
    /// - Returns: JwProtocol.TYPE_* 常量或 nil（unknown）← detectProtocolFromHtml
    static func detectProtocolFromHtml(_ html: String) -> String? {
        detectProtocolFromHtmlImpl(html)
    }

    /// T6 新增：URL + HTML 组合判型。
    /// URL 层命中（任何置信度）直接返回；否则 HTML 层；否则 nil。← detectProtocol
    /// ← kt:159 takeIf { it.isNotBlank() } — isNotBlank 含换行等全部 Unicode 空白
    static func detectProtocol(_ html: String, url: String? = nil) -> String? {
        if let u = url, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let t = detectProtocolFromUrlImpl(u.lowercased()) { return t }
        }
        return detectProtocolFromHtmlImpl(html)
    }

    /// T6 ①：URL 高置信有序判型链。小写化后的 URL 进来。 ← detectProtocolFromUrlImpl
    static func detectProtocolFromUrlImpl(_ u: String) -> String? {
        // ⓪ CAS / authserver 统一身份认证网关页：只是一跳中转，不当任何协议指纹。
        //    service= 参数里常带 jwglxt 等业务路径，不与业务锚点同判（fp.cas-gateway）。
        if u.range(of: #".*/cas/login.*"#, options: .regularExpression) != nil
            || u.range(of: #".*/authserver/login.*"#, options: .regularExpression) != nil
            || u.contains("/cas/login")
            || u.contains("/authserver/login") { return nil }

        // WebVPN 路径重写形态（/webvpn/<host>/、/http/<hex>/、hex-host.webvpn.）：
        // host 段不可见，CF/PKU/BNUZ/HNUST 的 host 级与弱路径锚点在重写下不可靠 → 跳过 ⑦-⑩
        if u.contains("/webvpn/")
            || u.range(of: #"/http/[0-9a-f]+/"#, options: .regularExpression) != nil
            || u.contains(".webvpn.") {
            // ← kt:350-351: host 锚点在 WebVPN 重写形态下仍保留 NUIT/KUST(两校 portal 域名
            //    整体内嵌于重写路径, 先于 /jwapp/ 归位, 否则被 WISEDU 吸走)
            if u.contains("jw.nuit.edu.cn") { return JwProtocol.TYPE_NUIT }
            if u.contains("i.kust.edu.cn")
                || u.contains("kust.edu.cn")
                || u.contains("kmust.edu.cn") { return JwProtocol.TYPE_KUST }
            if u.contains("/jwapp/") { return JwProtocol.TYPE_WISEDU }
            if u.contains("jwglxt")
                || u.range(of: #".*/xtgl(/|$).*"#, options: .regularExpression) != nil
                || u.contains("/kbcx/")
                || u.contains("xskbcx_cx")
                || u.contains("/jwtottxuxsysb/") { return JwProtocol.TYPE_ZF_NEW }
            if u.contains("default2.aspx")
                || u.contains("xskbcx.aspx") { return JwProtocol.TYPE_ZF }
            if u.contains("/jsxsd/")
                || u.range(of: #".*/jxd(/|$).*"#, options: .regularExpression) != nil
                || u.contains("logon.do")
                || u.contains("verifycode.servlet") { return JwProtocol.TYPE_QZ }
            if u.contains("xkaction.do")
                || u.contains("actiontype=6") { return JwProtocol.TYPE_URP }
            if u.contains("thissemestercurriculum")
                || u.contains("courseselect")
                || u.contains("ajaxstudentschedule") { return JwProtocol.TYPE_URP_NEW }
            return nil
        }

        // ① WISEDU — 金智 jwapp 微应用，URL 唯一锚点，优先级最高
        // ① 前置 host 锚点(← kt:374-375, 383): NUIT/KUST 两校 portal 域含 jwapp 路径,
        //    BUAA 新本研(byxt)与东北大学 NEU 同族同字段形态(复用 NEU parser; 旧
        //    jwxt.buaa.edu.cn 强智 iEAS 仍走下方 ②b)。三者必须先于通用 /jwapp/,
        //    否则被吸进 TYPE_WISEDU — WISEDU_FETCH_JS 走 wdkb/xskcb.do 通道拿不到
        //    arrangedList 必空课表(kt:376-382 注释原话)。
        if u.contains("jw.nuit.edu.cn") { return JwProtocol.TYPE_NUIT }
        if u.contains("i.kust.edu.cn")
            || u.contains("kust.edu.cn")
            || u.contains("kmust.edu.cn") { return JwProtocol.TYPE_KUST }
        if u.contains("byxt.buaa.edu.cn") { return JwProtocol.TYPE_NEU }
        if u.contains("/jwapp/") { return JwProtocol.TYPE_WISEDU }

        // ①a classic EAMS — server-rendered course table entry points (← kt:387-390).
        //    NWUPL 与 LIXIN 同一 TaskActivity 族, 不同路径。
        if u.contains("coursetableforstd")
            || u.contains("/edu/lesson/std/timetable") { return JwProtocol.TYPE_CLASSIC_EAMS }

        // ①a EAMS5 — supwisdom 平台（issue #25）：此前整条判型链无任何 EAMS5 锚点，
        //    连正确的 jxglstu 课表 URL 都判 null 走通用抓取必 0 课。
        //    锚点三件套: host (jxglstu / jw.ahu / jwxt.cumtb) + 路径级 /eams5-student/ +
        //    supwisdom 唯一路径约定 /for-std/（斜杠包围, forum-standard 不误命中）。
        if u.contains("jxglstu")
            || u.contains("/eams5-student")
            || u.contains("/for-std/")
            || u.range(of: #".*/for-std(/|$).*"#, options: .regularExpression) != nil
            || u.contains("jw.ahu.edu.cn")
            || u.contains("jwxt.cumtb.edu.cn") { return JwProtocol.TYPE_EAMS5 }

        // ①b CQU — 重庆大学统一门户（host 锚点；自建 REST，非 jwapp）
        // ★ Kotlin u.matches() = 全串匹配; Swift range(of:) 默认任意位置搜索 →
        //   必须 ^…$ 锚定, 否则 http://my.cqu.edu.cn.evil.com 这类串会误命中(kt:404)。
        if u.range(of: #"^https?://my\.cqu\.edu\.cn(/.*)?$"#, options: .regularExpression) != nil {
            return JwProtocol.TYPE_CQU
        }

        // ①c YETHAN — 西南交通大学逐专平台（host 唯一锚点，自建 JSON API）← kt:406-407
        if u.range(of: #"^https?://yhxt\.swjtu\.edu\.cn(/.*)?$"#, options: .regularExpression) != nil {
            return JwProtocol.TYPE_YETHAN
        }

        // ①d XJU_POST — 新疆大学研究生培养管理信息系统（Gwork 族, host 唯一锚点;
        //    yjspy 子域专属, xju.edu.cn 本科教务等其余子域不误判）← kt:409-411
        if u.range(of: #"^https?://yjspy\.xju\.edu\.cn(/.*)?$"#, options: .regularExpression) != nil {
            return JwProtocol.TYPE_XJU_POST
        }

        if u.contains("xkgo.ucas.ac.cn") && u.contains("/course/personschedule") {
            return JwProtocol.TYPE_UCAS
        }

        // ②b QZ_IEAS — 必须先于通用 /kbcx/ 规则
        if u.contains("/ieas2.1")
            || u.range(of: #".*/ieas2\.1(/|$).*"#, options: .regularExpression) != nil
            || u.contains("jwxt.buaa.edu.cn")
            || u.contains("jwxt-7001.e2.buaa.edu.cn") { return JwProtocol.TYPE_QZ_IEAS }

        // ② ZF_NEW — 新版正方 jwglxt 全系锚点
        //   a) /jwglxt/ 全路径 b) /xtgl(/|$) 边界（B1） c) /kbcx/ 接口
        //   d) xskbcx_cx（API 名，与 .aspx 不冲突） e) /jwtottxuxsysb/（来源不明，保留）
        if u.contains("jwglxt")
            || u.range(of: #".*/xtgl(/|$).*"#, options: .regularExpression) != nil
            || u.contains("/kbcx/")
            || u.contains("xskbcx_cx")
            || u.contains("/jwtottxuxsysb/") { return JwProtocol.TYPE_ZF_NEW }

        // ③ ZF — 老版正方 default2.aspx / xskbcx.aspx（.aspx 后缀，不与新正方 .html 混）
        if u.contains("default2.aspx")
            || u.contains("xskbcx.aspx") { return JwProtocol.TYPE_ZF }

        // ④ QZ — 强智入口四件套（B2: 替代裸 qz）
        if u.contains("/jsxsd/")
            || u.range(of: #".*/jxd(/|$).*"#, options: .regularExpression) != nil
            || u.contains("logon.do")
            || u.contains("verifycode.servlet") { return JwProtocol.TYPE_QZ }

        // ⑤ URP — 老 URP TeachRA / displayTag，精确锚点 xkAction.do（B3）
        if u.contains("xkaction.do")
            || u.contains("actiontype=6") { return JwProtocol.TYPE_URP }

        // ⑥ URP_NEW — 课表接口入口（URL 层高置信）
        if u.contains("thissemestercurriculum")
            || u.contains("courseselect")
            || u.contains("ajaxstudentschedule") { return JwProtocol.TYPE_URP_NEW }

        // ⑦ CF — 青果/乘方教务 URL 精确锚点（cf-chengfang-login.expected.json urlMarkers）
        if u.contains("/xsgrkbcx")
            || u.contains("/new/xskb")
            || u.contains("jxfw.gdut")
            || u.contains("zhjw.smu")
            || u.contains("jxgl.wyu")
            || u.contains("jw.hbmu") { return JwProtocol.TYPE_CF }

        // ⑦a CF_NEW — 新青果 NTSS (FullCalendar 形态): /new/student/xsgrkb 唯一路径锚点 ← kt:457-458
        if u.contains("/new/student/xsgrkb") { return JwProtocol.TYPE_CF_NEW }

        // ⑦b CHAOXING — 超星综合教务 (xsd=学生端 path, queryKbForGrdb 个人课表接口)
        if u.range(of: #".*/xsd(/|$).*"#, options: .regularExpression) != nil
            || u.contains("/xsd/pkgl/")
            || u.contains("querykbforgrdb")
            || u.contains("sdpkkblist") { return JwProtocol.TYPE_CHAOXING }

        // ⑧ PKU — 北大 IAAA / elective
        if u.contains("elective.pku")
            || u.contains("iaaa.pku") { return JwProtocol.TYPE_PKU }

        // ⑨ BNUZ — 北师珠 es.bnuz
        if u.contains("es.bnuz") { return JwProtocol.TYPE_BNUZ }

        // ⑩ HNUST — 湖南科大 kdjw / xxjw（HNUSTParser 由 T3 补，T6 先把路由做对）
        //    2026 起教务迁 .edu.cn 域（老 hnust.cn:8080 全 404），host 前缀不变
        if u.contains("kdjw.hnust")
            || u.contains("xxjw.hnust")
            || u.contains("jwgl.nepu") { return JwProtocol.TYPE_HNUST }

        // ⑪ 兜底 nil — 触发 HTML 二次判定
        return nil
    }

    /// T6 ②：HTML 页面级判型。大写原文传入，内部一次性 lowercase。 ← detectProtocolFromHtmlImpl
    /// CAS / authserver 网关页不设指纹（返回 nil 走兜底）。
    static func detectProtocolFromHtmlImpl(_ html: String) -> String? {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let lower = html.lowercased()
        let title = extractTitle(html)

        // ⓪ BNUZ 必须先于 ZF 判：北师珠页同含 __VIEWSTATE/CheckCode.aspx，
        //    唯一次级锚点是 form action="default.aspx"（老正方是 default2.aspx）。
        //    课表页无表单，用校名 title 兜底；含 default2.aspx 的页面（老正方混入提示）排除。
        if ((lower.contains("es.bnuz") || lower.contains("action=\"default.aspx\""))
                && !lower.contains("default2.aspx"))
            || title.contains("北师大珠海")
            || title.contains("珠海分校") { return JwProtocol.TYPE_BNUZ }

        // ① ZF_NEW — zftal-ui 资源 + 教学管理信息服务平台标题
        //    注意不用 "正方软件+版本v-" 页脚（老正方页脚同为 版本 V-x.y，会误吸）
        if lower.contains("zftal-ui-")
            || title.contains("教学管理信息服务平台")
            || lower.contains("login_slogin.html")
            || (title.contains("统一身份认证") && lower.contains("csrftoken")) { return JwProtocol.TYPE_ZF_NEW }

        // ② ZF — 老正方指纹三件套（__VIEWSTATE / GBK title / CheckCode.aspx）
        if lower.contains("__viewstate")
            || lower.contains("asp.net_sessionid")
            || title.contains("欢迎使用正方教务管理系统")
            || title.contains("正方教务管理系统")
            || lower.contains("checkcode.aspx") { return JwProtocol.TYPE_ZF }

        // ③ QZ — 强智资源路径 + 版权 + title
        if lower.contains("/framework/")
            || lower.contains("verifycode.servlet")
            || lower.contains("qzdatasoft.com")
            || title.contains("强智")
            || title.contains("教学一体化服务平台")
            || lower.contains("logon.do")
            || lower.contains("randomcode") { return JwProtocol.TYPE_QZ }

        // ④ NUIT/KUST JSON portal fingerprints ← kt:524-526
        if lower.contains("classdateandplace") { return JwProtocol.TYPE_NUIT }
        if lower.contains("queryaweekschedule") || lower.contains("resultsjsonarr") { return JwProtocol.TYPE_KUST }

        // ⑤ WISEDU — 业务回调路径
        if lower.contains("/jwapp/sys/")
            || (lower.contains("authserver/login") && lower.contains("execution=")) { return JwProtocol.TYPE_WISEDU }

        // ⑤ URP_NEW — SM3 加密资源 + URPNova
        if lower.contains("/js/sm3/")
            || lower.contains("sm3web.js")
            || lower.contains("urpnova")
            || lower.contains("/js/login/login.js") { return JwProtocol.TYPE_URP_NEW }

        // ⑦a CF_NEW — 新青果 NTSS: 课表页脚本路径特征, 必须先于 ⑦ CF
        //    (NTSS 页脚可能同含乘方字样, 路径锚点更窄更准) ← kt:538-542
        if lower.contains("/new/student/xsgrkb")
            || lower.contains("getcalendarweekdatas")
            || lower.contains("ntsscalendar") { return JwProtocol.TYPE_CF_NEW }

        // ⑥ URP — displayTag 老 URP
        if lower.contains("displaytag")
            || lower.contains("/checkcode")
            || lower.contains("/js/xkaction.js") { return JwProtocol.TYPE_URP }

        // ⑦ CF — 青果关键字（乘方教务/乘方科技；课表页页脚也有，不限 title）
        if lower.contains("乘方教务")
            || lower.contains("乘方科技")
            || lower.contains("/new/validatecode") { return JwProtocol.TYPE_CF }

        // ⑦b CHAOXING — 超星综合教务页脚 (Powered by ChaoXing)
        if lower.contains("powered by chaoxing")
            || lower.contains("超星综合教务") { return JwProtocol.TYPE_CHAOXING }

        // ⑧ PKU — 北大 IAAA / elective（课表页 title 含 北京大学选课系统）
        if lower.contains("iaaa.pku.edu.cn")
            || lower.contains("pku.edu.cn")
            || title.contains("北京大学选课系统")
            || (lower.contains("oauth.jsp") && lower.contains("appid"))
            || (lower.contains("syllabus") && lower.contains("elective")) { return JwProtocol.TYPE_PKU }

        // ⑨ BNUZ — es.bnuz host（action=default.aspx 形态已在 ⓪ 判）
        if lower.contains("es.bnuz") { return JwProtocol.TYPE_BNUZ }

        // ⑩ HNUST — 湖南科大（HTML 层特征由 T3 补）
        //    老域 hnust.cn / 新域 kdjw|xxjw.hnust.edu.cn 统一登录页 form-new-hnkjdx
        if lower.contains("hnust.cn")
            || lower.contains("hnust.edu.cn")
            || lower.contains("form-new-hnkjdx") { return JwProtocol.TYPE_HNUST }

        return nil
    }

    /// 抽 <title>...</title>（GBK/UTF-8 兼容，大文档用 indexOf 截窗，不依赖 SwiftSoup）
    /// - Returns: title 文本；无 title 返回空串 ← extractTitle
    static func extractTitle(_ html: String) -> String {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive) else {
            return ""
        }
        let start = startRange.lowerBound
        guard let openEnd = html[html.index(after: start)...].firstIndex(of: ">") else { return "" }
        guard let closeRange = html.range(of: "</title>", options: .caseInsensitive, range: html.index(after: openEnd)..<html.endIndex) else { return "" }
        return String(html[html.index(after: openEnd)..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// T6 诊断 API：命中的指纹特征列表（T9 接到导入失败错误提示）。 ← detectProtocolHitFeatures
    static func detectProtocolHitFeatures(_ html: String) -> [String] {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let lower = html.lowercased()
        let title = extractTitle(html)
        var hits: [String] = []
        if lower.contains("zftal-ui-") { hits.append("zftal-ui-") }
        if title.contains("教学管理信息服务平台") { hits.append("title:教学管理信息服务平台") }
        if lower.contains("__viewstate") { hits.append("__VIEWSTATE") }
        if lower.contains("asp.net_sessionid") { hits.append("ASP.NET_SessionId") }
        if lower.contains("verifycode.servlet") { hits.append("verifycode.servlet") }
        if lower.contains("/framework/") { hits.append("/framework/") }
        if lower.contains("qzdatasoft.com") { hits.append("qzdatasoft.com") }
        if lower.contains("/jwapp/sys/") { hits.append("/jwapp/sys/") }
        if lower.contains("/js/sm3/") { hits.append("/js/sm3/") }
        if lower.contains("urpnova") { hits.append("URPNova") }
        if lower.contains("displaytag") { hits.append("displaytag") }
        if lower.contains("/js/xkaction.js") { hits.append("/js/xkAction.js") }
        if lower.contains("/checkcode") { hits.append("/checkCode") }
        if lower.contains("乘方教务") { hits.append("乘方教务") }
        if lower.contains("乘方科技") { hits.append("乘方科技") }
        if lower.contains("/new/student/xsgrkb") { hits.append("/new/student/xsgrkb") }
        if lower.contains("getcalendarweekdatas") { hits.append("getCalendarWeekDatas") }
        if lower.contains("ntsscalendar") { hits.append("ntsscalendar") }
        if lower.contains("iaaa.pku.edu.cn") { hits.append("iaaa.pku.edu.cn") }
        if lower.contains("pku.edu.cn") { hits.append("pku.edu.cn") }
        if title.contains("北京大学选课系统") { hits.append("北京大学选课系统") }
        if lower.contains("es.bnuz") { hits.append("es.bnuz") }
        if title.contains("北师大珠海") || title.contains("珠海分校") { hits.append("title:北师大珠海") }
        if lower.contains("action=\"default.aspx\"") { hits.append("form action=default.aspx") }
        if lower.contains("hnust.cn") { hits.append("hnust.cn") }
        if lower.contains("hnust.edu.cn") { hits.append("hnust.edu.cn") }
        if lower.contains("form-new-hnkjdx") { hits.append("form-new-hnkjdx") }
        return hits
    }

    /// T5 新增: 解析 ZF_NEW_FETCH_JS 的回调 raw。 ← parseZfNewBridgeResult
    ///
    /// 返回 (ok, payload, kind):
    ///   - ok=true  → payload 是喂 JwNewZfParser 的源 (kbList 纯 JSON 字符串)
    ///   - ok=false → kind ∈ {SESSION_EXPIRED, EMPTY_SEMESTER, FORMAT_ERROR, NOT_ON_TIMETABLE, OTHER}
    /// 任何 JSON 解析异常都返回 ok=false, kind=FORMAT_ERROR (不抛)。
    static func parseZfNewBridgeResult(_ raw: String) -> (ok: Bool, payload: String, kind: String) {
        guard let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (false, "parse failed", "FORMAT_ERROR")
        }
        if (obj["ok"] as? Bool) ?? false {
            // ← kt:243-251: optString("format", "") — 缺键默认空串 → != "zf_new" → OTHER;
            //   data 缺失/纯空白 → FORMAT_ERROR (Kotlin isBlank 语义)
            let d = obj["format"] as? String ?? ""
            let dataStr = obj["data"] as? String ?? ""
            if d != "zf_new" {
                return (false, "", "OTHER")
            } else if dataStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (false, "", "FORMAT_ERROR")
            } else {
                return (true, dataStr, "")
            }
        } else {
            let kind = obj["kind"] as? String ?? "OTHER"
            let err = obj["err"] as? String ?? ""
            return (false, err, kind)
        }
    }

    /// 把 JwCourse 列表转成 sleepy 的 CourseEntity 列表 ← toCourseEntities
    static func toCourseEntities(_ courses: [JwCourse], tableId: Int64, defaultColor: String) -> [CourseEntity] {
        return courses.map { jw in
            let step = max(jw.endNode - jw.startNode + 1, 1)
            return CourseEntity(
                groupId: "",
                tableId: tableId,
                courseName: jw.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : jw.name,  // ← kt ifBlank
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
    /// v1.0.56 T10 对齐(← kt:661-723): 新增 smartConfigJson(智慧节次配置随导入落库,
    /// 否则用户配置被丢弃) 与 periodTable(非 nil = 解析出了独立节次 → 同事务自动建
    /// 同名作息表并绑定; 名字走全局唯一名顺延, 撞名自动加后缀)。
    /// 默认值保持既有调用方源码兼容(新增而非改名)。
    static func importAsNewTable(
        _ db: AppDatabase,
        courses: [JwCourse],
        tableName: String,
        startDate: String? = nil,
        timeJson: String = "",
        nodesPerDay: Int = 0,
        smartConfigJson: String = "",
        periodTable: PeriodTableEntity? = nil
    ) throws -> Int64 {
        if courses.isEmpty {
            throw NSError(domain: "JwImport", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "课程列表为空，请确认已到达课表页面"])  // ← kt:672 全角逗号
        }

        // ★ 整个建表 + 落库包在单一事务里:中途失败回滚,避免留下空课表。 ← db.withTransaction
        return try db.dbQueue.write { dbw in
            let tableDao = db.timeTableDao
            let courseDao = db.courseDao

            // ★ 用 autoGenerate (id=0) 让 GRDB 分配真实主键,避免手动 max(id)+1 撞旧 ID 覆盖既有课表。
            // ← kt:681-683: 非空 startDate 先归一到所在周周一(应用约定 startDate=周一,
            //   issue #5), 解析失败原样返回; 空白视为未填走学期默认。
            let resolvedStartDate = (startDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? Self.normalizeStartDate(startDate!) : nil)
                ?? computeCurrentSemesterStart()
            let maxNode = nodesPerDay > 0 ? nodesPerDay : courses.map { max($0.startNode, $0.endNode) }.max() ?? 1
            var newTable = TimeTableEntity(
                name: tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "导入的课表" : tableName,  // ← kt ifBlank
                startDate: resolvedStartDate,
                nodesPerDay: maxNode,
                timeJson: timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TimeTableUtils.DEFAULT_TIME_JSON : timeJson,
                isDefault: true,  // 导入的课表设为默认,widget 直接展示
                smartConfigJson: smartConfigJson,
                id: 0
            )
            // v1.0.56 T10: 自动作息表先落库拿 id — 建表时同名, 但全局唯一名墙:
            // 名字与既有课表/作息表撞 → 顺延后缀。建课表时直接带绑定。(← kt:694-707)
            // 事务内直读直插: DAO 的 getAll() 走 db.read 会在写事务里重入死锁,
            // 故此处用事务句柄 dbw 内联查询(语义同 Room getAll, 仅取 name 列参与撞名)。
            // 禁 try? 吞错: Android Room 事务内 insert 失败 → 整笔事务回滚(kt:676 withTransaction),
            // 静默继续会留下未绑定的空课表 — 与 Android 行为劈叉。
            let autoPeriodTableId: Int64? = try periodTable.map { pt in
                var pt = pt
                let courseNames = try TimeTableEntity.fetchAll(dbw, sql: "SELECT * FROM time_tables").map { $0.name }
                let periodNames = try PeriodTableEntity.fetchAll(dbw, sql: "SELECT * FROM period_tables").map { $0.name }
                pt.name = TimeTableUtils.suggestUniqueName(pt.name, courseTableNames: courseNames, periodTableNames: periodNames)
                pt.nodesPerDay = max(pt.nodesPerDay, 1)  // ← kt coerceAtLeast(1)
                return try db.periodTableDao.insertInDb(dbw, pt)
            }
            newTable.periodTableId = autoPeriodTableId
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

    /// 归一 yyyy-MM-dd 字符串到其所在周周一; 解析失败原样返回。
    /// ← DateUtils.kt:60-65 normalizeStartDate(mondayOf + fullDate, catch → 原样),
    /// 应用约定 startDate=周一(issue #5), 写库前统一走这里。
    /// 回格式化比对 == 原文 = Java LocalDate.parse 的严格语义(2026-13-45 / 2026-09-1
    /// 这类非法/欠宽输入必须原样返回, 不许 Calendar 宽松顺延成别的日期)。
    static func normalizeStartDate(_ startDate: String) -> String {
        guard let parsed = DateUtils.parseDate(startDate),
              DateUtils.fullDate(parsed) == startDate else { return startDate }
        return DateUtils.fullDate(Calendar.isoMondayOfWeek(parsed))
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

/// 解析分派单点: 空 protocolType → 全候选按 confidence 裁决; 声明 type → 工厂表精确解析。
/// 永不抛出 —— 失败时把 error 文案与 attempts 一起交回调用方,
/// 供 JwParseDiagnostics.classify 生成面向用户的诊断文案(导入 0 课/解析失败)。
enum JwParseDispatch {
    struct Outcome {
        let courses: [JwCourse]
        let attempts: [ParserAttemptSnapshot]
        let error: String?
    }

    static func parse(_ html: String, _ protocolType: String) -> Outcome {
        // ← kt:106 protocolType.isBlank() — isBlank 含换行等全部 Unicode 空白
        if protocolType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 未知协议(URL 直接登录): 跑全部候选按 confidence/课程数裁决
            let best = JwParserRegistry.selectBest(html, declaredType: nil)
            return Outcome(courses: best.0, attempts: best.1, error: nil)
        }
        do {
            let r = try JwImportViewModel.parseHtmlStatic(html, protocolType)
            return Outcome(courses: r.courses, attempts: r.attempts, error: nil)
        } catch let e as JwParseError {
            return Outcome(courses: [], attempts: e.attempts, error: e.message)
        } catch {
            return Outcome(courses: [], attempts: [],
                           error: "parser 解析异常: \(Swift.type(of: error))")
        }
    }

    /// 兼容旧 throws 语义(JwImportViewModel.parseHtml)
    static func parseOrThrow(_ html: String, _ protocolType: String) throws -> [JwCourse] {
        let out = parse(html, protocolType)
        if let e = out.error { throw JwParseError(message: e, attempts: out.attempts) }
        return out.courses
    }
}
