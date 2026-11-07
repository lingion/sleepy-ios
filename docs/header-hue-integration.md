# Header / hue 独立迁移证据

目标：`integration-parity-v1063`；来源：`parity-v1063` 工作区（包含未提交修正）。按目标增量合入，未整文件覆盖来源。

## 实现

- legacy 表头新增 dash / center 设置、显式预览 override 和持久偏好订阅。列宽、列轴使用 `legacyTimeColumnPx`；center 渲染以实际内容宽居中。three-line 悬挂算法保持原样。
- hide-time 标签单行分支与宽度下限保留；真实网格也改走 `legacyTimeWidthDp`，隐藏时间时不受 alignment 影响。
- `AppearanceScreen` 持有 `HueEditingSession`：`current` 可修改/提交，`baseline` 为进页固定值。移除遮蔽新版组件的私有同名实现，唯一真实调用现在指向独立 `CourseColorSection.swift`。
- 独立配色组件保留写侧 `resolveAnchor` 同源解析、持久 hueMap 优先、空表占位；接入真实前五组课程（含别名）、统一底色选择与预览。提交种子后重算、刷新 hueStore 和小组件，基线不重置。
- PR36 六滑杆（网格缩放、周缩放、圆角、stack/rail/fold）接入 ghost 基线和投影。源 `captureBaselines()` 每次 onAppear 都覆盖基线，迁移时加首次捕获守卫，六个基线随 `ScheduleDisplayContent` 身份保持。父值量化和提交回调保留；目标文件原有 16 行独立注释完整保留。

## 验证

- 初始回归：7 项失败；header/hue 增量后定向 5 项通过。追加六滑杆测试时 9 项中仅新增 2 项失败。
- 最终 `python3 scripts/tests/test_header_hue_regression.py`：**9/9 通过**，纯 Swift 子进程串行执行。
  - 抽取生产几何策略：center 宽 86 / 轴 43，dash 宽 100 且等于旧算法，空列宽 0。
  - 抽取生产 hue session：提交 300 后基线仍 180；新会话基线 300；负值/超范围与非有限值处理。
  - 抽取生产 `captureBaselines()`：修改六值后再次捕获仍保留首次六值；新实例捕获新值。
  - 接线断言覆盖页面→独立组件→HueSlider、hide-time、真实课程组、统一底色、六滑杆及量化回写。
- 源脚本 Swift 行为区的 **13 条 assert 全部保留**；原有测试文件未修改。
- 以下 7 个文件 `swiftc -parse` 退出码 0：

```sh
swiftc -parse \
  Sleepy/ui/component/HueSlider.swift \
  Sleepy/ui/component/PeriodHeaderCellContent.swift \
  Sleepy/ui/component/CourseTableView.swift \
  Sleepy/ui/screen/mine/PeriodHeaderSettingsScreen.swift \
  Sleepy/ui/screen/mine/AppearanceScreen.swift \
  Sleepy/ui/screen/mine/CourseColorSection.swift \
  Sleepy/ui/screen/mine/ScheduleDisplayScreen.swift
```

验证边界：parse 仅证明语法，不代表整工程类型检查/构建通过。未运行 xcodebuild、模拟器或像素验收。六滑杆投影沿用 PR36 固定 **11pt 近似轨道内缩**，不是系统 Slider 轨道实测；真实轨道对齐、系统字号/RTL、SwiftUI 页面生命周期仍需后续运行验收。

## 集成依赖与边界

本切片未修改 `AppPrefs.swift`。核对时目标仍需追加：

- `static let KEY_PERIOD_HEADER_TIME_ALIGNMENT = "period_header_time_alignment"`
- `func getPeriodHeaderTimeAlignment() -> String`：默认 `dash`，仅 `center` 原样返回，其他值回落 `dash`。
- `func setPeriodHeaderTimeAlignment(_ value: String)`：接受 `dash` / `center`，通过现有 `sp()` 存储。

引用的三键为 `appearance_header_time_alignment`、`appearance_header_alignment_dash`、`appearance_header_alignment_center`；本地化资源由主 agent 处理，本切片未改资源。

`CourseTableView.swift` 仅改 header 参数、偏好订阅、宽度/轴与其调用；未动 drag/render row 算法、parser、工程文件。未 commit/push。
# 2026-11-03 主会话追加复核

- 真实预览原先丢弃 colorMode/color/groupRows，且缺持久 hue 时使用试算色，和首页不一致。
- 新增 CourseColorPreview，保留同表组行，真实预览走首页 pickCourseColorSwiftUIWithGroupRows；试算仅供空课表占位。
- 新增 CourseColorPreviewTests 四项：CUSTOM 优先于统一色、缺 hue 回退、AUTO 同表组行、前五组保留后续成员；工程级 XCTest 尚待运行。
- test_header_hue_regression.py 原断言锁死字符串 `hueMap[key] ?? value`，恰好要求已确认错误的试算回退。该断言改为检查真实组行、持久 hue/CLASSIC 分支和首页共用入口，并禁止真实模型调用 planHuesForGroups；其余行为断言保留。2026-11-03 重跑 9/9 通过，仅代表此脚本覆盖范围。
- NativeBaselineSlider 已接入六滑杆并注册。当前值和基线使用相同原生 UISlider 的范围、frame 和 semanticContentAttribute，基线隐藏轨道且不接收触摸/辅助功能事件；不再估算 11pt 轨道内缩。VoiceOver/键盘修改在没有 touchUp 时也提交。原静态断言曾锁死 11pt，现改为验证原生几何共用、方向接线及非交互语义；9/9 重跑通过。实际 RTL 显示仍待原生验收。
