# 系统取色设计（已批准）

## 目标与边界

使用公开上游窗口 tint 派生现有 HSV/M3 角色配色，真实跟随深浅外观与增加对比度。最低 iOS 15.6，不换 HCT。颜色来源只允许 `windowTint` 或 `fallback`；主屏幕图标着色、壁纸颜色没有已核实公开 getter，不能出现在成功来源或用户承诺中。

## 数据流

`所属 UIWindow.tintColor → SystemColorProbe → 当前 AppRoot 的快照 → SleepyThemeProvider → SystemColorScheme → CustomSchemeDeriver`

当前 key 且 foregroundActive 的窗口将同一快照写入独立 App Group defaults key，供 full-color Widget 与 CourseColorWriteGlue 读取。每个 AppRoot 保有自己的快照，不观察其他窗口覆盖本窗口颜色。共享消费者使用最近活跃窗口；非活跃窗口不得覆盖。采样器不写任何课程数据库。

快照记录 schemaVersion、algorithmVersion、source、fallbackReason、RGB、系统 dark/contrast、window 标识。RGB 为不透明、8-bit sRGB；转换失败/透明色拒绝，灰度合法。旧/损坏/未知版本快照回落默认紫色并保留 fallback 身份。无窗口时不得拿其他窗口缓存冒充现场信号。

## 采样与生命周期

SwiftUI probe 安装于 AppRoot 的主题 tint 输出之外。实际颜色只读 probe 所属 `window.tintColor`，不读 probe/subview 的 tint，不反推生成色。窗口本身 dimmed 时保持上次稳定样本；窗口/trait/tint/foreground/key-window 事件重新评估。更新异步合并，内容相同不重复发布或 reload widgets；销毁注销观察者。不枚举全局 key window。

## 派生

复用 CustomSchemeDeriver 的 HSV 模板数学，仅系统分支新增单种子入口。primary/secondary 共种子色相，tertiary 色相 +60°，surface 使用同色相低饱和；种子近灰时全角色族保持中性，不回落紫色。色族饱和度受种子饱和度限制。前景色按 sRGB 相对亮度对比度选择/修正，普通文字至少 4.5:1，增加对比度目标 7:1（必要时调整对应底色）；error 语义族固定，亦检验对比度。输出不透明，不依赖隐式 trait 再解析。

## 接线

- `themeKey` 与 `themeMode` 保持正交；预设、自定义主题不受系统 seed 更新覆盖。
- 内层 overlay provider 读取根注入的同一 snapshot；presentation 显式带入 snapshot。
- Widget 的 fullColor 使用共享快照和渲染环境深浅/对比度。accented 与 vibrant 分别建模、分别分支；颜色处理由系统完成，不回写 seed。
- 课程 system anchor 调用相同派生入口，取共享快照 appearance；仅原有显式课程操作读取，不订阅系统变化做 DB 重算。
- SystemThemeCard 显示当前来源及 fallback。全局 localization 由主会话接入，临时 fallback 文案不得泄露原始 key。

## 官方依据（2026-11 查阅）

- https://developer.apple.com/documentation/uikit/uicolor/tintcolor — “current tint color of the app or trait hierarchy”，iOS 15。
- https://developer.apple.com/documentation/uikit/uiview/tintcolor — 沿视图祖先继承，未设置时使用 system-defined color；dimmed 会影响值。
- https://developer.apple.com/documentation/uikit/uicolor/resolvedcolor(with:) — 在所属视图 trait 下解析。
- https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast — 取值来自用户设置。
- https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances — fullColor/accented/vibrant 三种模式。
- https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass — clear/tinted 系统渲染不是 RGB getter。

## 验证限制

本轮只写实现、测试与文档，不在本机运行编译/测试/模拟器，不派代理，不提交推送。CI 通过前不宣称编译或测试通过。真实主屏幕 tint 同步不属于本实现承诺。
