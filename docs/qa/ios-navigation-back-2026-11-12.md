# iOS 课表创建与返回回归（2026-11-12）

## 修复范围与原因

- 课表管理 → 添加课表：来源 SwiftUI 页面被独立 `UIHostingController` 覆盖后，普通状态绑定不能可靠触发导航注册更新。导航状态改为稳定存储与赋值后的显式通知，刷新读取实时值；每次激活有独立会话，旧退出回调不能清除重开的页面或替换后的条目。
- 导入页原生侧滑：原先全区域 `DragGesture` 即使没有键盘也参与手势竞争。移除该手势，iOS 16+ 使用 `scrollDismissesKeyboard`；iOS 15 的探针只设置最近祖先 `UIScrollView.keyboardDismissMode`，拆除时恢复。导航手势代理保留 UIKit 的公开仲裁回调，仅应用现有业务返回门禁。
- 新建空白课表 → 取消：删除草稿实体时原生退出动画尚未结束，编辑器可能重新渲染缺失数据页。返回前保留同 ID 的退出快照，不修改草稿删除时机，也不借用其他课表；真实缺失数据页保留返回入口。

## 环境与结果

Xcode 27.2（27B52），iPhone 17 模拟器，iOS 27.0，Debug。串行执行，禁用签名和自动依赖解析；本轮没有使用真机或执行复杂课程拖动。

| 运行 | 结果 | 覆盖 |
| --- | --- | --- |
| `final-navigation-unit` | 37 项通过，0 失败 | 导入生命周期、导入展示、父级叠加导航、课程深链、快速添加预填、新建课表及默认值 |
| `final-navigation-ui` | 8 项通过；2 项因测试定位错误失败 | 添加课表反复返回及原生侧滑、两种外观的空白课表取消、父级草稿保留、取消后重启、完整文本导入，以及设置页往返 |
| `final-holiday-navigation` | 2 项因旧标题断言失败 | 输入正常后进入调休页，旧测试仍等待改名前的英文标题 |
| `final-holiday-title-navigation` | 2 项因同名父级入口误判失败 | 调休页标题与编辑页入口同名，通用文本查询无法判断子页是否退出 |
| `final-holiday-scoped-navigation` | 2 项通过，0 失败 | 顶栏标识与子页独有控件共同判断返回，两种外观的调休设置往返 |

最终 37 项相关测试与 10 项不同 UI 用例均通过；UI 成功结果由首次运行的 8 项与修正定位后的 2 项组成，不把前面的失败运行记为全绿。生产代码在这几次 UI 定向重跑之间没有变化。

`final-navigation-ui` 的两项失败均发生在复制课表名称输入阶段：通用后代查询选中了继承同一标识的 `StaticText`，没有打开键盘。查询改为 `app.textFields["table_copy_name"]`，清空、输入分别等待真实字段值；原有课表身份、草稿保留、当前表不变和不持久化取消内容的断言全部保留。

定向重跑随后暴露了另一处旧测试文案：等待 `holiday_page_title` 的英文旧标题，实际页面已经使用 `settings_holiday_title_rules`（`Holidays and make-up classes`）。只修改测试中预期的标题，未改动产品文案或跳过页面断言。

该标题也用于编辑页的入口行，因此仅按文本查询并要求返回后不存在，会把父页入口误认为未退出的子页。最终测试按已有 `settings_topbar_title` 标识和精确文案查询顶栏，返回后同时要求顶栏及两张表的子页分段按钮消失、编辑器存在。原有草稿、当前课表与取消内容不落盘的断言继续执行。

37 项测试中，新增三项真实 UIWindow / UINavigationController 集成用例验证反复打开关闭、实际弹栈动画中重开，以及可选条目替换后旧回调不能误关新条目。测试探针不通过额外观察对象或读取绑定促使来源页面重绘。

UI 数据回归在取消空白表后移除播种参数、正常重启，比较原课表的 ID 和名称，并检查原有五门课程仍存在。多次新建、改名、取消后，原导入页的完整文本和展开状态继续保留。

## 诊断证据与边界

- 状态诊断中，普通 `@State` 绑定不能可靠关闭被覆盖的来源页；仅增加读取依赖仍不能处理退出动画中重开。显式状态通知和会话保护后，三项实窗回归通过。
- 保留原键盘拖动手势时，同一原生边缘返回用例失败；移除后 `native-keyboard-edge` 的边缘返回和完整文本导入均通过，最终 UI 回归再次通过这两条路径。
- iOS 15 兼容分支已随 App 编译，但没有可用的 iOS 15 运行时用于执行验证。
- 本轮没有重新测量启动速度、FPS 或 Release 真机性能，也未把空白编辑器缺失数据的所有历史时序声称为已稳定复现。

## 复跑入口

在 Xcode 选择 Sleepy scheme、iPhone 模拟器，串行运行以下类：

```text
SleepyTests/ImportPresentationLifecycleTests
SleepyTests/ImportPresentationTests
SleepyTests/OverlayParentNavigationTests
SleepyTests/CourseDeepLinkNavigationTests
SleepyTests/QuickAddPrefillTests
SleepyTests/NewTableImportTests
SleepyTests/NewTableImportDefaultTests
```

UI 用例：`ManageImportUITests` 中的添加课表反复返回、空白课表取消与重启、父级草稿保留、原生外观取消和完整文本导入；`EditTableHolidayUITests` 的两项；`NavigationTransitionCanvasUITests` 的经典子页创建往返及两种外观的设置往返。

本机原始命令 JSON、日志与 xcresult 位于任务工作目录 `work/ios-navigation-back/`，运行名与上表一致；这些临时产物没有加入源码提交。
