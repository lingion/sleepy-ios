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
    private static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    /// 追加钉死参数后启动(幂等: 重复调用不会重复追加)。
    func sleepyLaunch() {
        if !launchArguments.contains(Self.forcePillArg) {
            launchArguments.append(Self.forcePillArg)
        }
        launch()
    }
}
