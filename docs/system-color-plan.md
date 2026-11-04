# 系统取色 Implementation Plan

**Goal:** 将已批准的窗口 tint 方案接入 App、全彩 Widget 和课程 anchor。

**Architecture:** 窗口局部采样和环境快照负责实时 UI；独立 App Group 快照负责跨进程消费；单个纯派生入口负责所有 system 配色。

**Tech Stack:** SwiftUI、UIKit、WidgetKit、Foundation UserDefaults、现有 HSV 引擎，iOS 15.6。

## Global Constraints

- 不派代理、不本机编译/测试/模拟器、不提交推送；CI 执行所有新增测试。
- 保留所有集成代码，尤其 AppRoot quickadd 回调。全局 localization/工程 membership 由主会话维护。
- 不读私有 API，不声称壁纸/主屏幕取色，不自动改课程 DB。

## 执行步骤

状态：以下勾选代表源码/测试已编写并做静态复核，**不代表 CI 已运行或通过**。最终收录与验收见 `system-color-freeze.md`。

### 1. 快照与共享存储
- [x] 新增 `Sleepy/theme/SystemColorSeed.swift`：`SystemColorSnapshot` Codable/Equatable，严格版本/RGB/来源验证；`SystemColorSeedStore.read/write` 独立 key 与可注入 defaults。
- [x] 新增 `SleepyTests/SystemColorTests.swift`：灰度、透明/非有限输入、损坏/未来版本快照、去重与跨实例 roundtrip。

### 2. 单种子 HSV 配色
- [x] 在 `CustomSchemeDeriver.swift` 增加系统单种子入口，保留现有自定义入口行为。
- [x] 新增 `SystemColorScheme.swift`：统一 fallback/seed 解析及对比度修正；固定系统算法版本 1。
- [x] 编写 CI 测试红绿蓝黄青品红灰黑白 × 深浅 × 对比度，验证关键前景/底色数值比值和不透明色。

### 3. 窗口采样与 App 接线
- [x] 新增 `SystemColorProbe.swift`：UIViewRepresentable、所属窗口读取、tint/traits/key/active 事件、异步去重、注销。`snapshot` binding 向 AppRoot 发布，只有 active key window 写共享快照。
- [x] `SleepyApp.swift` 根 State、上游 probe、环境注入和 sheet 主题接线；保留路由/quickadd 回调。
- [x] `Theme.swift` provider 的 system 分支调用统一 resolver，内层 provider 继承同一环境快照。
- [x] `SystemThemeCard` 显示来源与明确 fallback，并列出交主会话的文案 key。
- [x] 新增 UIKit CI 测试：两个窗口局部采样、自身 child tint 不污染、dimming 保持稳定、重复刷新不发布。

### 4. Widget 与课程 anchor
- [x] `WidgetContent.swift` system 分支改用统一入口，移除 systemPurple 再覆盖；accented/vibrant 独立策略。
- [x] `WidgetBackgroundCompat.swift` 兼容 iOS 15.6，使用真实模式枚举传递；必要 Widget 调用点仅做参数转接。
- [x] `CourseColorWriteGlue.swift` 替换 system primary 与 sRGB anchor 转换分支；保持现有 DB 写入边界。
- [x] 编写 CI 测试同一快照下 App/Widget/anchor 一致，宿主模式保留身份、不由宿主颜色生成 seed。

### 5. 冻结
- [x] 静态检查差异、availability、target 归属依赖、回调保护；`git diff --check`。
- [x] `system-color-freeze.md` 记录实际文件、测试契约、localization key、未验证能力。
- [ ] 主会话收录 target/localization 并执行线上 CI。

### 6. 追加批准的动效集成
- [x] PresentOverlay 底页接 `SleepyNavigationUnderlay`；自绘 tab/右栏接 `SleepyNavigationContent`。
- [x] App 普通按钮接 0.98 按压；网格与前景冲突卡两处拖课起点显式 opt out。
- [x] `ThemeColorVector.swift`：30 槽 × RGBA，稳定 AnimatableModifier；Reduce Motion 直接终值。
- [x] 根布局 tint/平板表面色下沉读取每帧 environment；新增插值与宿主 state 测试。
- [x] 通过 `os(iOS) && !WIDGET_EXT && !WATCH_APP` 隔离仅 App 可用的动效依赖。

## CI 执行契约

线上构建 App/Widget 并保持 deployment target 15.6；运行新增 `SystemColorTests`/probe 测试及现有 `CustomThemeTests`、`WidgetThemeModeTests`、`CourseColorWriteGlueTests`、`CourseColorCommitBoundaryTests`。新测试不得修改/删除现有断言。运行环境不足以提供旧 OS 时报告缺口，不把“最新 OS 编译成功”等同旧 OS 运行验证。
