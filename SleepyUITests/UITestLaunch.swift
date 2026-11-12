// UITestLaunch.swift — UITests 统一启动入口(2026-10-26 底栏自适应改造)
//
// 背景: 全量 UITests 按自绘 pill_<id> 标识导航(4 个 tab 切换、深链回跳等),
// 原生 TabBar(iOS 26+)没有这些标识。resolver 现按系统能力自动选原生,
// 因此所有 UI 测试启动必须钉死自绘: -SLEEPY_FORCE_PILL_NAV(同 NavStyleResolver.forcePillArg)。
// 缺省几何 = 悬浮(与改造前 prefs 未写入时 navFloating=true 的行为一致)。
//
// 各文件 setUp 里原有的 launchArguments(种子数据/语言/环境)保持不变,
// 这里只负责追加钉死参数并 launch。

import XCTest

extension XCUIApplication {
    /// Match the public pager identifier independently of its UIKit container type.
    var scheduleWeekPager: XCUIElement {
        descendants(matching: .any).matching(identifier: "schedule_week_pager").firstMatch
    }

    private static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    /// 追加钉死参数后启动(幂等: 重复调用不会重复追加)。
    func sleepyLaunch() {
        if !launchArguments.contains(Self.forcePillArg) {
            launchArguments.append(Self.forcePillArg)
        }
        // scheme 的 TZ 只注入测试 runner, 被测 App 是独立进程不继承。
        // GitHub runner 为 UTC: 种子按设备时区取"本周一", App 再按 Asia/Shanghai
        // 民事日换算周次, 二者错开 → 冷启动不在 Week 1。显式给 App 同一时区。
        if launchEnvironment["TZ"] == nil {
            launchEnvironment["TZ"] = "Asia/Shanghai"
        }
        launch()
    }
}

// MARK: - 自绘药丸底栏的 tab 切换(条件等待 + 重试)
//
// ★ 2026-10-31 新增。背景: UIElementAuditUITests.testA6_ImportSheet_Dark 曾
//   偶发失败(单跑/分组/全量三次均未复现), 失败时的无障碍层级显示 app 仍停在
//   Schedule 页 —— 即「pill_manage 的 tap 没生效」。旧写法是
//   `pill_manage.tap(); sleep(1)`, 没有任何「切换真的发生了」的断言, 于是
//   tap 丢失时会一路滑到「manage_import 未找到」, 报错现场与真正病因隔得很远。
//
// 机制: 悬浮/贴底两套 bar 的 tab 操作都是叠在图标+文字上的 **透明 overlay Button**
//   (Color.clear.contentShape(Rectangle())), 它不是图标本身 —— 命中依赖 overlay
//   处在命中测试树里。若点击落在 bar 重建(首帧落位 / refreshNavMode 重判 /
//   tab 切换过渡动画)的那一帧, hit-test 可能落在旧树或动画中的视图上, 动作被吞。
//
// 做法: ①用「目标 tab 的 isSelected trait」作为切换成功的条件(不靠 sleep)；
//      ②条件不满足就重试点击(最多 3 次), 重试之间给一次过渡时间。
//      这样「tap 被吞」变成一次显式重试, 而不是一个下游的玄学超时。
//
// 注意: 选中态用 accessibilityAddTraits(.isSelected) 表达, 断言用
//   `element.isSelected` —— XCUITest 的 isSelected 读的是该 trait。

extension XCUIApplication {

    /// 某个 tab 是否处于选中态(读 .isSelected trait)。
    ///
    /// ★ 单独存在的原因: 元素查询在 XCUITest 里很贵(每次 ~200-900ms),
    ///   轮询时只查目标 tab(1 次)而不是四个 tab 全查(4 次)。
    private func isPillTabSelected(_ tabId: String) -> Bool {
        let el = descendants(matching: .any)["pill_\(tabId)"]
        return el.exists && el.isSelected
    }

    /// 当前选中的 tab id(自绘 bar 的 pill_<id> 中带 .isSelected trait 的那个)。
    /// 仅用于失败信息, 不在轮询热路径上调用。
    private var selectedPillTabId: String? {
        let ids = ["schedule", "today", "manage", "mine"]
        for id in ids where isPillTabSelected(id) {
            return id
        }
        return nil
    }

    /// 切到指定 tab, 并断言「真的切过去了」。
    ///
    /// - Parameters:
    ///   - tabId: schedule / today / manage / mine
    ///   - timeout: 等待切换生效的总时长。默认 30s 而非 10s ——
    ///     实测「我的」页首屏很重(tap 后 app 要 ~16s 才 idle),
    ///     10s 会在切换其实已生效时提前判失败(见 b5-test.log 的 11 条同因失败)。
    ///   - file/line: 断言定位(透传给 XCTAssert*)
    /// - Returns: 切换是否成功(失败即已断言失败, 调用方可直接继续)。
    @discardableResult
    func switchToPillTab(_ tabId: String,
                         timeout: TimeInterval = 30,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> Bool {
        let target = descendants(matching: .any)["pill_\(tabId)"]
        guard target.waitForExistence(timeout: timeout) else {
            XCTFail("底栏 tab pill_\(tabId) 未出现", file: file, line: line)
            return false
        }

        // 已经是目标 tab → 无需点击。
        if isPillTabSelected(tabId) { return true }

        // 条件等待: 选中 trait 翻转 = 切换生效(不给固定 sleep)。
        //
        // ★ 不用 XCTNSPredicateExpectation: 它的 predicate 在**后台线程**求值,
        //   而 XCUIElement 的查询(isSelected / descendants)只在主线程有效 ——
        //   后台求值拿不到可靠的选中态, 结果是「tab 其实已经切过去了,
        //   但谓词永远为 false」⇒ 误报切换失败(实测: 失败信息里
        //   「当前选中: mine」本身就是选中态)。
        //   改为在主线程手动轮询。
        let deadline = Date().addingTimeInterval(timeout)
        var lastTapAt = Date.distantPast
        while Date() < deadline {
            // tap 可能被吞(bar 重建/动画帧)→ 每 1s 补一次点击。
            if Date().timeIntervalSince(lastTapAt) >= 1.0 {
                tapPillTab(tabId)
                lastTapAt = Date()
            }
            if isPillTabSelected(tabId) { return true }
            usleep(200_000)   // 0.2s
        }

        XCTFail("切换到底栏 tab \(tabId) 失败(选中态未翻转, 当前选中: \(selectedPillTabId ?? "无"))",
                file: file, line: line)
        return false
    }

    /// 点一次自绘 bar 的 tab。
    /// 优先用元素命中点; 元素不可命中(命中测试树正在重建)时退回坐标点击 ——
    /// 坐标由元素 frame 换算, 命中的是 tab 座位本身, 不依赖 overlay Button 在树里。
    private func tapPillTab(_ tabId: String) {
        let el = descendants(matching: .any)["pill_\(tabId)"]
        guard el.exists else { return }
        if el.isHittable {
            el.tap()
            return
        }
        let frame = el.frame
        guard frame.width > 0, frame.height > 0 else { return }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
