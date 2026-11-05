# 表盘小组件扩展设计 — 6 个 widget kind（尺寸矩阵 / 刷新 / 数据层）

> 状态: 设计已确认（2026-11-05），待实现计划分解后开工
> 分支: `feat/watch-widget-kinds` · 基线: `master@72c822c`
> 触发: 表盘用户反馈「想要更多不同尺寸、不同类型的小组件」——现状仅 1 个 kind

## 1. 背景与现状

- **手机端**（`SleepyWidget`）有 5 个 widget（今日 / 两日 / 周列表 / 周视图 / 周网格），手表端只有 1 个。
- **手表端现状**：`SleepyWatchWidgets` 仅 `WatchNextClassWidget`（「下一节课」），单一 kind 覆盖 4 个 accessory family（`.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` / `.accessoryCorner`），四形态同一语义。
- 数据链路已成型，本次新 kind 全部复用：
  - extension 进程独立，经 App Group（`group.com.lingion.sleepy`）直读手表本地 GRDB（`WatchComplicationData` 纯函数装载模式）；
  - 手表快照 apply 后 `WatchStore.applySnapshot` 末尾调用 `WidgetCenter.shared.reloadAllTimelines()`（`SleepyWatch/WatchStore.swift:226`）——新增 kind 自动受益，无需新接线；
  - 部署目标 watchOS 10.0（覆盖 Series 4 / SE 一代以上），四个 accessory family 均可用。

## 2. 目标 / 非目标

**目标**：新增 5 个独立 widget kind（共 6 个），每个 kind 支持语义成立的 family，让用户在表盘槽位和智能叠放里「按尺寸挑内容」。

**非目标**（本次不做）：

- ControlWidget（watchOS 26.0+ 门槛，此前已定不牺牲老设备覆盖面）；
- AppIntents 可配置 widget（手表配置体验差、发现性差，与诉求相反）；
- 智能叠放 ranking 调优（先用系统默认）；
- 修改现有 `WatchNextClassWidget` 的任何行为。

## 3. 决策摘要

| # | 决策 | 结论 |
|---|------|------|
| 1 | 架构取向 | **6 个独立静态 kind**（否决：合并为 5 个、AppIntents 可配置） |
| 2 | 一览 vs 概览 | 一览 = 面向「接下来上什么」；概览 = 面向「今天整体」 |
| 3 | 兜底文案 | 「假期中」「今日已结束」「今日无课」「明日无课」 |
| 4 | 实时性 | 新 kind 用系统相对时间文本（`.relative`/`.timer`），真机验证；不达预期退回「静态值 + 边界刷新」；现有「下一节」不动 |
| 5 | 文档落点 | 本文件（`docs/` 公开侧）；实现计划进 `tasks/`（本地侧） |

## 4. Widget kinds 清单（6 个）

| # | Kind ID | 名称 | 语义 | 状态 |
|---|---------|------|------|------|
| 1 | `WatchNextClassWidget` | 下一节课 | 下一节 + 倒计时 | 现有，不动 |
| 2 | `WatchCurrentClassWidget` | 正在上的课 | 进行中课程 + 进度 / 剩余 | 新增 |
| 3 | `WatchTodayListWidget` | 今日课程一览 | 后续课程列表 / 剩余节数 | 新增 |
| 4 | `WatchTodayOverviewWidget` | 今日概览 | 第 N 周 + 今日总节数 + 首末时间 | 新增 |
| 5 | `WatchTomorrowWidget` | 明日课程 | 明日课程列表 / 节数 / 首节时间 | 新增 |
| 6 | `WatchWeekWidget` | 第 N 周 | 周数 + 学期进度 | 新增 |

`SleepyWatchWidgetsBundle` 由 1 项扩到 6 项。所有 kind 均为 `StaticConfiguration`，无配置参数。

## 5. 尺寸（family）矩阵与兜底

每个 kind 声明 `supportedFamilies` 为下表有描述的组合；视图按 family 分派（沿用现有 `WatchComplicationEntryView` 的 switch 模式）。

| Kind | circular | corner | rectangular | inline | 兜底（无课 / 学期外） |
|------|----------|--------|-------------|--------|----------------------|
| 正在上的课 | 进度环 + 剩余分钟 | 剩余分钟（accent） | 课名 / 教室 · 剩余 xx 分 / 进度条 | 进行中 · 课名 | 课间 → 退化为「下一节」语义；全天无课 → 「无课」 |
| 今日一览 | 剩余 N 节 | N 节 | 进行中（置顶，若有）+ 未开始课，最多 3 行（时间 + 课名） | 今日还有 N 节 | 已上完 → 「今日已结束」；全天无课 → 「今日无课」 |
| 今日概览 | 今日 N 节（大数字） | N 节 | 第 N 周 / 今日 N 节 / 首末时间 | 第 N 周 · 今日 N 节 | 学期外 → 「假期中」 |
| 明日课程 | 明日 N 节 | N 节 | 明日前 3 节（时间 + 课名） | 明日 N 节 · 08:00 起 | 明日无课 → 「明日无课」；学期外 → 「假期中」 |
| 第 N 周 | 大号周数 + 学期进度环 | N 周 | 第 N 周 / 共 M 周 + 进度条 | 第 N 周 / 共 M 周 | 学期外 → 「假期中」 |

**口径细则**（实现与测试按此执行）：

- **「剩余 N 节」（一览）** = 今天未开始的课数（`start > now`）；N=0 且当天有课 → 「今日已结束」。
- **一览列表** = 进行中的课（若有，置顶并标注）＋ 未开始的课，最多 3 行。
- **「今日 N 节」（概览）** = 今天全部课数（含已上完）；**首末时间** = 首课开始 – 末课结束（无课 → 兜底文案）。
- **正在上的课** = `start ≤ now < end`；切到课间后显示下一节信息（倒计时/课名），与现有「下一节」口径一致。
- **明日** = 明日日期上的**有效星期**（`effectiveDayOfWeek(table.id, tomorrow)`，调休换日）＋ 明日所在周的 `inWeek` 过滤 ＋ **明日**学期状态（不能只看今天）。
- **第 N 周** = `currentWeek(startDate, now)`（1 基）；进度 = `week / maxWeek` clamp `[0, 1]`。
- 课程时间反解（`ownTime`/`irregular` 直读时钟 vs `timeJson` 反解）、课名**恒原名**（不套别名）——全部与现有表盘 widget 同口径。

**深链**：today 类 kind → `sleepy://watch?tab=today`；明日课程 / 第 N 周 → `sleepy://watch?tab=schedule`（现有 tab 枚举 `today|schedule|mine`）。

## 6. 刷新策略（Timeline）

沿用现有 provider 模式：`entry[0] = now`，`entry[1] = 下一边界`，`policy = .atEnd` 到期续期。

| Kind | 边界 |
|------|------|
| 正在上的课 / 今日一览 | 课程上下课边界（边界时刻 +60s 防同刻竞态） |
| 今日概览 / 明日课程 / 第 N 周 | 次日 00:05 兜底重算 |

- 快照同步触发的 `reloadAllTimelines()` 已存在（见 §1），全 kind 自动刷新，无新接线。
- **相对时间文本**：倒计时 / 剩余分钟优先用 `Text(date, style: .relative/.timer)`（表盘上由系统自动走字；智能叠放为静态）。实现时以真机验证为准；若表盘形态不生效 → 退回静态值 + 边界刷新。现有「下一节」不统一改造。

## 7. 数据层设计

新增 **`Sleepy/widget/WatchAgendaCore.swift`**（纯 Foundation，无 UIKit / WidgetKit 依赖）：

- API 草案：`currentClass(...)` / `todayAgenda(...)`（列表 + 剩余数 + 总数 + 首末）/ `tomorrowAgenda(...)` / `semesterProgress(...)`。
- 复用共享层：`WidgetTableResolver`、`ScheduleRepository`、`DateUtils`、`TimeTableUtils`、`HolidayTransferHelper`。
- 现有 `WatchComplicationData` 中内联的私有副本（`nowMinutes` / `courseStartEndMin` / `slotLabel` / `timeRange`）提取到 core 共用——**不产生第三份副本**；`WatchComplicationData` 保留「下一节」原有口径，改为调用 core。
- 编译路径（共享源码模式，无需改 `project.yml`）：
  - → `SleepyWatch`（手表主 app）
  - → `SleepyWatchWidgets`（extension，共享源）
  - → `Sleepy` target（iOS，供 `SleepyTests` 单测；文件须保持无平台专属 API）

## 8. 视图与文件布局（`SleepyWatchWidgets/`）

```
WatchWidgets.swift              — 6 个 kind 声明 + WidgetBundle（现有文件扩展）
WatchComplicationProvider.swift — 「下一节」provider（现有，不动）
WatchComplicationViews.swift    — 「下一节」视图（现有，不动）
WatchComplicationData.swift     — 「下一节」装载（改为调用 WatchAgendaCore）
WatchTimelineSupport.swift      — 新增：共享刷新点计算（各新 provider ≈15 行）
WatchCurrentClassViews.swift    — 新增：正在上的课 4 形态视图
WatchTodayListViews.swift       — 新增：今日一览 4 形态视图
WatchTodayOverviewViews.swift   — 新增：今日概览 4 形态视图
WatchTomorrowViews.swift        — 新增：明日课程 4 形态视图
WatchWeekViews.swift            — 新增：第 N 周 4 形态视图
```

视图规范沿用现有：`.widgetAccentable()` 系统着色、不强套主题色、`widgetURL` 深链。

## 9. 本地化

- 新增键（5 语言 `en/es/ja/zh-Hans/zh-Hant` 同步）：5 组 `display_name` / `description` + 词组（正在 / 剩余 x 分钟 / 今日还有 N 节 / 今日 N 节 / 第 N 周 / 共 M 周 / 明日 N 节 / 假期中 / 今日已结束 / 明日无课 等），命名沿用 `watch_` 前缀。
- 先审计复用现有键：`watch_mark_now`（进行中）/ `watch_countdown_done`（今日课程已结束）/ `no_course` / `unit_minutes` / `watch_mark_next` 等 21 个 `watch_*` 键 5 语言已齐。
- 键集一致性：新增键逐语言回填（沿用各语言文件现有书写格式），按项目 G3 字符串 parity 口径自检。

## 10. 测试与验证

- **单元测试** `SleepyTests/WatchAgendaCoreTests.swift`（Sleepy target 编译 core，可直接测）：
  - 开课瞬间 / 课中 / 下课瞬间 / 课间退化 / 全天无课；
  - 剩余列表（上完剔除、跨午休、进行中置顶）；
  - 明日调休换日（被调休为上课日 / 休息日两侧）+ 明日学期状态；
  - 学期外 / 未开学全空 → 兜底分支；
  - 周数首末周 / `maxWeek` 缺失兜底 / 进度 clamp；
  - `ownTime` / `irregular` 课程首末时间。
- **构建**：`xcodegen generate` + watchOS scheme 构建 SUCCEEDED（SleepyWatchWidgets 三 target 共源编译不回归）。
- **渲染**：Xcode Preview 每 kind × 4 family + 模拟器快照核对。
- **真机**：gallery 出现 6 个 widget、四槽位渲染正确、相对时间文本走字行为实测（决定 §6 实时性方案去留）。真机安装需用户按一次安装键。

## 11. 风险与未决

| 风险 | 等级 | 应对 |
|------|------|------|
| 相对时间文本在表盘不按预期走字 | 中 | 真机验证先行；退回静态值 + 边界刷新（即有方案） |
| 一览 / 概览入口区分度不被用户理解 | 低 | 上线后看反馈；必要时后续合并或调整描述文案 |
| 6 个 kind 撑爆 gallery 可读性 | 低 | 每个 kind 配清晰 display_name / description；Apple 自带 app 同类先例 |
| extension 编译面扩大（共享源新文件） | 低 | core 保持纯 Foundation；三 target 构建闸兜底 |

## 12. 决策记录（备选方案）

| 方案 | 结论 | 理由 |
|------|------|------|
| A. 6 个独立 kind | ✅ 采纳 | 直接对应「很多不同类型」；发现性最好；静态配置零接线成本 |
| B. 合并为一览+概览单 kind（共 5 个） | ✗ | 少一个入口，但削弱用户可见的「类型数量」 |
| C. 1-2 个 AppIntents 可配置 widget | ✗ | 手表配置体验差、与诉求相反；ControlWidget/AppIntents 此前已明确回避 |
