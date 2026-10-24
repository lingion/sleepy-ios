// JwWebViewFrameCapture.swift — ← JwWebViewFrameCapture.kt (500 行)
//
// T7 — WebView 抓取结果的 frame 级分析与决策。纯 Foundation, 不 import UIKit/WebKit。
//
// 分层: WebView 内 CAPTURE_FRAMES_JS 只负责"把每个可达 frame 的 outerHTML + 路径 + 跨域标记"
// 按 JSON 回传(Swift 信任它的输出, 不在 JS 做决策); 本文件在 Swift 上重建 frame 树、
// 扫锚点、做登录页指纹判定、ready-check 重试决策。全部逻辑可被 XCTest 直接构造 JSON 驱动。

import Foundation

// MARK: - 状态枚举
enum FrameCaptureStatus {
    case ok
    case emptySemester
    case wrongPage
    case crossDomainIframeBlocked
    case containerEmptyAfterDelay
    case sessionExpired
    case iframeNavPending
    case unknown
}

// MARK: - 抓取结果
struct FrameCaptureResult {
    let selectedFramePath: [String]?       // 选中 frame 的路径; nil = 没有可达 frame
    let html: String                       // 选中 frame 的 outerHTML; 无选中时为 ""
    let matchedAnchors: [String]           // 命中的锚点子集
    let courseCount: Int
    let status: FrameCaptureStatus
    let blockedFrames: [String]            // 跨域 frame "name@domain"
    let retryCount: Int
    let maxDepthReached: Int
    let skippedFrames: [String]
    let diagnosticHint: String
    let allFrames: [(path: String, html: String)]

    init(
        selectedFramePath: [String]?,
        html: String,
        matchedAnchors: [String],
        courseCount: Int = 0,
        status: FrameCaptureStatus,
        blockedFrames: [String] = [],
        retryCount: Int = 0,
        maxDepthReached: Int = 0,
        skippedFrames: [String] = [],
        diagnosticHint: String = "",
        allFrames: [(String, String)] = []
    ) {
        self.selectedFramePath = selectedFramePath
        self.html = html
        self.matchedAnchors = matchedAnchors
        self.courseCount = courseCount
        self.status = status
        self.blockedFrames = blockedFrames
        self.retryCount = retryCount
        self.maxDepthReached = maxDepthReached
        self.skippedFrames = skippedFrames
        self.diagnosticHint = diagnosticHint
        self.allFrames = allFrames
    }
}

// MARK: - Frame 快照
struct FrameSnapshot: Hashable {
    let frameName: String?    // 顶层固定 "(top)"
    let frameSrc: String?
    let depth: Int            // 顶层 0
    let parentPath: [String]  // 顶层 []
    let outerHTML: String?    // nil = 跨域或读取失败
    let blockedDomain: String?
}

struct FrameSnapshotList {
    let url: String
    let declaredMaxDepth: Int
    let frames: [FrameSnapshot]

    /**
     * 解析 CAPTURE_FRAMES_JS 回传 JSON。
     * 结构: {"ok":true,"url":"...","depth":N,"frames":[{name,src,depth,path:[],html,blocked},...]}
     * 容错: ok=false / frames 缺失 / 某 frame 的 html 为 null / blocked 非空 都不抛异常。
     */
    static func fromJson(_ json: String) -> FrameSnapshotList {
        if json.isEmpty { return FrameSnapshotList(url: "", declaredMaxDepth: 0, frames: []) }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FrameSnapshotList(url: "", declaredMaxDepth: 0, frames: [])
        }
        let url = obj["url"] as? String ?? ""
        let depth = (obj["depth"] as? Int) ?? 0
        let framesArr = obj["frames"] as? [[String: Any]] ?? []
        var snapshots: [FrameSnapshot] = []
        for f in framesArr {
            let htmlStr = f["html"] as? String ?? ""
            let blockedStr = f["blocked"] as? String ?? ""
            let pathArr = f["path"] as? [String] ?? []
            let nameStr = f["name"] as? String ?? ""
            let srcStr = f["src"] as? String ?? ""
            snapshots.append(FrameSnapshot(
                frameName: nameStr.isEmpty ? nil : nameStr,
                frameSrc: srcStr.isEmpty ? nil : srcStr,
                depth: (f["depth"] as? Int) ?? 0,
                parentPath: pathArr,
                outerHTML: htmlStr.isEmpty ? nil : htmlStr,
                blockedDomain: blockedStr.isEmpty ? nil : blockedStr
            ))
        }
        return FrameSnapshotList(url: url, declaredMaxDepth: depth, frames: snapshots)
    }
}

// MARK: - 树遍历与锚点判定
enum FrameTraversalTree {

    /// 锚点集 — 与 parser 容器选择器对齐(Table1/blacktab/kbtable/kbgrid_table_0/kblist_table/
    /// kbList/kbxx/timetable/_dgdata)。
    static let ANCHORS: [String] = [
        "Table1", "blacktab", "kbtable", "kbgrid_table_0", "kblist_table",
        "kbList", "kbxx", "timetable", "_dgdata"
    ]

    private static func anchorNeedle(_ anchor: String) -> [String] {
        if anchor.hasPrefix("_") {
            // 尾部子串锚点 (ASP.NET 命名容器前缀): id="..._dgdata"
            return ["\(anchor)\"", "\(anchor)'"]
        }
        return ["id=\"\(anchor)\"", "id='\(anchor)'", "class=\"\(anchor)\"", "class='\(anchor)'"]
    }

    /// 扫锚点: 返回 ANCHORS 的命中子集, 顺序保持 ANCHORS 原序
    static func findAnchors(_ html: String) -> [String] {
        if html.isEmpty { return [] }
        let lower = html.lowercased()
        return ANCHORS.filter { anchor in
            anchorNeedle(anchor).contains { lower.contains($0.lowercased()) }
        }
    }

    /// 跨域 frame 列表: "frameName@domain"
    /// frameName 缺省回退语义与 Android `frameSrc.trim().takeLastWhile { it != '/' }` 对齐:
    /// 先去空白再取最后一段 '/' 后缀 (src 以 '/' 结尾时得到空串), 而非剪掉尾斜杠再取段。
    static func findBlockedFrames(_ snapshots: FrameSnapshotList) -> [String] {
        return snapshots.frames.compactMap { f in
            guard let domain = f.blockedDomain else { return nil }
            let name: String
            if let n = f.frameName {
                name = n
            } else if let src = f.frameSrc {
                let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
                name = String(trimmed.split(separator: "/", omittingEmptySubsequences: false).last ?? Substring(trimmed))
            } else {
                name = "unknown"
            }
            return "\(name)@\(shortDomain(domain))"
        }
    }

    private static func shortDomain(_ src: String) -> String {
        if let url = URL(string: src), let host = url.host { return host }
        return String(src.prefix(80))
    }

    /// 登录页指纹表 — 关键词小写包含即命中, ≥2 条命中才判 SESSION_EXPIRED
    static let LOGIN_FINGERPRINTS: [(String, String)] = [
        ("__viewstate", "zf/ASP.NET"),
        ("type=\"password\"", "zf/ASP.NET"),
        ("checkcode.aspx", "zf"),
        ("logon.do", "qz"),
        ("verifycode.servlet", "qz"),
        ("logintoxk", "qz"),
        ("login_slogin.html", "zf_new"),
        ("/authserver/login", "cf"),
        ("/iaaa/oauth.jsp", "pku"),
        ("appid=syllabus", "pku"),
        ("action=\"default.aspx\"", "bnuz"),
        ("j_spring_security_check", "urp_new"),
        ("cas/login", "sso-cas"),
        ("请输入密码", "通用"),
        ("会话已超时", "通用"),
        ("请重新登录", "通用"),
        ("您的账号在其它地方登录", "qz-顶号")
    ]

    /// 登录页判定: 对一份 frame HTML 独立打分; ≥2 命中 → true。
    /// 硬指纹 logout-redirect 单条即判 (JwParseDiagnostics.LOGOUT_REDIRECT)。
    static func looksLikeLoginPage(_ html: String) -> Bool {
        if html.isEmpty { return false }
        let range = NSRange(html.startIndex..., in: html)
        if JwParseDiagnostics.LOGOUT_REDIRECT.firstMatch(in: html, range: range) != nil { return true }
        let lower = html.lowercased()
        var score = 0
        for (kw, _) in LOGIN_FINGERPRINTS {
            if lower.contains(kw.lowercased()) { score += 1 }
        }
        return score >= 2
    }

    /// Kotlin maxByOrNull 语义: 并列取最先出现者 (Swift max(by:) 取最后, 故自实现)。
    private static func deepestFirst(_ frames: [FrameSnapshot]) -> FrameSnapshot? {
        var best: FrameSnapshot? = nil
        for f in frames where best == nil || f.depth > best!.depth { best = f }
        return best
    }

    /// 硬指纹 logout-redirect 帧搜索 — 单条即判, 返回最深的可达 frame
    static func findLogoutRedirectFrame(_ snapshots: FrameSnapshotList, maxDepth: Int) -> FrameSnapshot? {
        return deepestFirst(snapshots.frames
            .filter { $0.outerHTML != nil && $0.depth <= maxDepth }
            .filter { f in
                let html = f.outerHTML!
                let range = NSRange(html.startIndex..., in: html)
                return JwParseDiagnostics.LOGOUT_REDIRECT.firstMatch(in: html, range: range) != nil
            })
    }

    struct Candidate {
        let snapshot: FrameSnapshot
        let anchors: [String]
        let order: Int
    }

    /// skippedFrames = 可达但无锚点、且不是任一候选 frame 的祖先(或本身)的 frame 名。
    /// 祖先链 frame 是通往锚点容器的路径, 不算"被跳过"。
    static func computeSkipped(
        _ snapshots: FrameSnapshotList,
        maxDepth: Int,
        candidates: [Candidate]
    ) -> [String] {
        var ancestorSet = Set<FrameSnapshot>()
        for c in candidates {
            // parentPath 是祖先 frame 名链(如 ["(top)","main"]), 名字对应即视为祖先
            let names = Set(c.snapshot.parentPath)
            for f in snapshots.frames {
                if let name = f.frameName, names.contains(name) { ancestorSet.insert(f) }
            }
            ancestorSet.insert(c.snapshot)
        }
        return snapshots.frames
            .filter { $0.outerHTML != nil && $0.depth <= maxDepth }
            .filter { findAnchors($0.outerHTML!).isEmpty }
            .filter { !ancestorSet.contains($0) }
            .compactMap { $0.frameName }
    }

    /// ③ 候选排序: 锚点数降序 → 深度降序 → DOM 顺序升序
    static func rankedCandidates(_ snapshots: FrameSnapshotList, maxDepth: Int = 8) -> [Candidate] {
        var result: [(FrameSnapshot, [String], Int, Int, Int)] = []
        for (idx, f) in snapshots.frames.enumerated() {
            guard let html = f.outerHTML, f.depth <= maxDepth else { continue }
            let anchors = findAnchors(html)
            if anchors.isEmpty { continue }
            result.append((f, anchors, idx, anchors.count, f.depth))
        }
        // 锚点降序 → 深度降序 → DOM 顺序升序
        result.sort { a, b in
            if a.3 != b.3 { return a.3 > b.3 }
            if a.4 != b.4 { return a.4 > b.4 }
            return a.2 < b.2
        }
        return result.map { Candidate(snapshot: $0.0, anchors: $0.1, order: $0.2) }
    }

    ///
    /// 选择规则(优先级自上而下, 来自 11 份 case.json 的 frameStrategy 字段):
    ///  ① 可达 = outerHTML != null 且 depth <= maxDepth(默认 8)。
    ///  ② 对每个可达 frame 独立 findAnchors; 命中者进候选。
    ///  ②b 全无锚点时 UCAS personSchedule 双指纹回退。
    ///  ③ 候选排序: 锚点数降序 → 深度降序 → DOM 顺序升序; 排序第一名为初选。
    ///  ④ 全部可达 frame 均无锚点: 登录指纹 > 跨域 > WRONG_PAGE。
    ///  ⑤ 全部 frame 不可达(顶层都跨域): blocked 非空 → CROSS_DOMAIN_IFRAME_BLOCKED, 否则 WRONG_PAGE。
    ///
    static func selectBestFrame(_ snapshots: FrameSnapshotList, maxDepth: Int = 8) -> FrameCaptureResult {
        let blocked = findBlockedFrames(snapshots)
        let reachable = snapshots.frames.filter { $0.outerHTML != nil && $0.depth <= maxDepth }
        let maxDepthReached = snapshots.frames.map { $0.depth }.max() ?? 0
        // 全帧 outerHTML — 排查包 1-dom/ 对齐桌面 collector (每个可达 frame 一个 html 文件)
        let allFrames: [(path: String, html: String)] = reachable.map { f in
            ((f.parentPath + [f.frameName ?? "(top)"]).joined(separator: "_"), f.outerHTML ?? "")
        }
        // 硬指纹 logout-redirect 先于锚点 + 先于 looksLikeLoginPage 评分 (见 helper doc)
        if let logoutFrame = findLogoutRedirectFrame(snapshots, maxDepth: maxDepth) {
            return FrameCaptureResult(
                selectedFramePath: logoutFrame.parentPath + [logoutFrame.frameName ?? ""],
                html: logoutFrame.outerHTML ?? "",
                matchedAnchors: [],
                status: .sessionExpired,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: [],
                diagnosticHint: "检测到登录页/会话过期特征(\(logoutFrame.frameName ?? "(top)") 含 logout.aspx 跳转脚本)，请重新登录后再点「导入此页」",
                allFrames: allFrames
            )
        }
        // ②③ 候选
        let candidates = rankedCandidates(snapshots, maxDepth: maxDepth)
        let skipped = computeSkipped(snapshots, maxDepth: maxDepth, candidates: candidates)
        if let best = candidates.first {
            return FrameCaptureResult(
                selectedFramePath: best.snapshot.parentPath + [best.snapshot.frameName ?? ""],
                html: best.snapshot.outerHTML ?? "",
                matchedAnchors: best.anchors,
                status: .ok,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped,
                allFrames: allFrames
            )
        }

        // ②b UCAS personSchedule 网格页: 容器是通用 bootstrap class (table-striped…),
        //    无任何 id=/class= 锚点命中 ANCHORS 集 (case #18)。以页面双指纹识别:
        //    <title>个人课表 + 课程格详情链接 /course/coursetime/ — 与 JwUcasParser
        //    HTML 路径 confidence 锚一致。SEP 门户页无这两特征, 不误吸。
        if let ucasFrame = deepestFirst(reachable.filter({ f in
            guard let html = f.outerHTML else { return false }
            let lower = html.lowercased()
            return lower.contains("<title>个人课表</title>") && lower.contains("/course/coursetime/")
        })) {
            return FrameCaptureResult(
                selectedFramePath: ucasFrame.parentPath + [ucasFrame.frameName ?? ""],
                html: ucasFrame.outerHTML ?? "",
                matchedAnchors: ["ucas-personSchedule"],
                status: .ok,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped,
                allFrames: allFrames
            )
        }

        // ④ 全部可达 frame 均无锚点
        //  - 任一可达 frame looksLikeLoginPage → SESSION_EXPIRED
        //    多个 frame 同时命中时取最深的(顶层 frameset 可能因注释/说明文字含弱指纹词,
        //    真正的登录表单在更深的内层 frame — case #8)
        if let loginFrame = deepestFirst(reachable.filter { looksLikeLoginPage($0.outerHTML!) }) {
            return FrameCaptureResult(
                selectedFramePath: loginFrame.parentPath + [loginFrame.frameName ?? ""],
                html: loginFrame.outerHTML ?? "",
                matchedAnchors: [],
                status: .sessionExpired,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped,
                diagnosticHint: "检测到登录页/会话过期特征(frame=\(loginFrame.frameName ?? "(top)"))，请重新登录后再点「导入此页」",
                allFrames: allFrames
            )
        }
        //  - 存在 blocked frame → CROSS_DOMAIN_IFRAME_BLOCKED
        if !blocked.isEmpty {
            return FrameCaptureResult(
                selectedFramePath: nil,
                html: "",
                matchedAnchors: [],
                status: .crossDomainIframeBlocked,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped,
                diagnosticHint: blocked.joined(separator: "、"),
                allFrames: allFrames
            )
        }
        //  - 否则 WRONG_PAGE (空壳 iframe 由调用方 captureWithRetry 按重试情况升格 IFRAME_NAV_PENDING)
        let firstReachable = reachable.first
        return FrameCaptureResult(
            selectedFramePath: firstReachable.map { $0.parentPath + [$0.frameName ?? ""] },
            html: firstReachable?.outerHTML ?? "",
            matchedAnchors: [],
            status: .wrongPage,
            blockedFrames: blocked,
            maxDepthReached: maxDepthReached,
            skippedFrames: skipped,
            diagnosticHint: reachable.isEmpty ? "页面无可读 frame" : "当前页面未检测到课表容器",
            allFrames: allFrames
        )
    }

    ///
    /// 解析驱动的候选回退: 把"锚点命中"升级为"锚点命中 且 parser 产出 > 0 课"。
    ///
    /// - Parameter parse: 单个 frame HTML 的解析函数 — 抓取层不依赖解析层, 通过高阶函数注入。
    /// - Returns: 课程数最大的候选(并列取排序靠前者); 全部 0 课 → status=emptySemester(锚点命中过)。
    ///
    static func rankAll(
        _ snapshots: FrameSnapshotList,
        maxDepth: Int = 8,
        parse: (String) throws -> [Any]
    ) -> FrameCaptureResult {
        let blocked = findBlockedFrames(snapshots)
        let maxDepthReached = snapshots.frames.map { $0.depth }.max() ?? 0
        // 硬指纹 logout-redirect 先于锚点 + 先于 parser 解析 (见 helper doc)
        if let logoutFrame = findLogoutRedirectFrame(snapshots, maxDepth: maxDepth) {
            return FrameCaptureResult(
                selectedFramePath: logoutFrame.parentPath + [logoutFrame.frameName ?? ""],
                html: logoutFrame.outerHTML ?? "",
                matchedAnchors: [],
                status: .sessionExpired,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: [],
                diagnosticHint: "检测到登录页/会话过期特征(\(logoutFrame.frameName ?? "(top)") 含 logout.aspx 跳转脚本)，请重新登录后再点「导入此页」"
            )
        }
        let candidates = rankedCandidates(snapshots, maxDepth: maxDepth)
        let skipped = computeSkipped(snapshots, maxDepth: maxDepth, candidates: candidates)

        var bestCount = 0
        var bestCandidate: Candidate? = nil
        for c in candidates {
            let count = ((try? parse(c.snapshot.outerHTML!))?.count) ?? 0
            if count > bestCount {
                bestCount = count
                bestCandidate = c
            }
        }

        if let bestCandidate = bestCandidate, bestCount > 0 {
            return FrameCaptureResult(
                selectedFramePath: bestCandidate.snapshot.parentPath + [bestCandidate.snapshot.frameName ?? ""],
                html: bestCandidate.snapshot.outerHTML ?? "",
                matchedAnchors: bestCandidate.anchors,
                courseCount: bestCount,
                status: .ok,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped
            )
        }

        if let first = candidates.first {
            // 有锚点候选但全部 0 课 → EMPTY_SEMESTER
            return FrameCaptureResult(
                selectedFramePath: first.snapshot.parentPath + [first.snapshot.frameName ?? ""],
                html: first.snapshot.outerHTML ?? "",
                matchedAnchors: first.anchors,
                courseCount: 0,
                status: .emptySemester,
                blockedFrames: blocked,
                maxDepthReached: maxDepthReached,
                skippedFrames: skipped,
                diagnosticHint: "已尝试 \(candidates.count) 个含课表容器的 frame, 均未解析出课程"
            )
        }

        // 候选为空 → 与 selectBestFrame 一致(登录指纹 > 跨域 > WRONG_PAGE)
        return selectBestFrame(snapshots, maxDepth: maxDepth)
    }
}

// MARK: - 渲染就绪度检查 (ready-check 重试决策)
enum RenderReadinessChecker {
    /// 延迟渲染容器 — 新正方 grid/list 视图 + 老正方 Table1Wrap
    static let DELAYED_CONTAINER_ANCHORS: [String] =
        ["Table1Wrap", "kbgrid_table_0", "kblist_table", "kbcontent", "timetable_con"]

    enum Readiness {
        case ready
        case delay
        case giveUp
    }

    /// - Parameters:
    ///   - html: 本次抓取选中的 frame HTML(不是整页拼接)
    ///   - retryCount: 已完成的重试次数(0=首次)
    static func check(_ html: String, retryCount: Int) -> Readiness {
        if retryCount >= 3 { return .giveUp }
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .delay }
        let lower = html.lowercased()
        let hasDelayed = DELAYED_CONTAINER_ANCHORS.contains { lower.contains($0.lowercased()) }
        if hasDelayed {
            let loadingText = lower.contains("加载中") || lower.contains("loading")
                || lower.contains("数据加载") || lower.contains("暂无数据")
            let gridEmpty = lower.contains("kbgrid_table_0") && !lower.contains("kbcontent")
            let listEmpty = lower.contains("kblist_table") && !lower.contains(".title ")
            if loadingText || gridEmpty || listEmpty { return .delay }
        }
        return .ready
    }

    ///
    /// case.json #7 专款: 空 iframe 壳判定 — html 非空但结构上只有空 head/body。
    /// 判定 true: 去空白后长度 < 60 且 (含 "<html" 或含 "<body") 且不含 "<table" 不含 "<div" 不含 "<form"。
    ///
    static func checkBlankShell(_ html: String) -> Bool {
        let stripped = html.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        if stripped.count >= 60 { return false }
        let lower = html.lowercased()
        if !(lower.contains("<html") || lower.contains("<body")) { return false }
        if lower.contains("<table") || lower.contains("<div") || lower.contains("<form") { return false }
        return true
    }

    static func delayedStatus(retryCount: Int) -> FrameCaptureStatus {
        retryCount >= 3 ? .containerEmptyAfterDelay : .ok
    }
}
