# 教务导入返回导航切片

## 上游核实：不是依据旧审计推定

只读比较本地 Android 仓库 `/Users/kerrylee/sleepy` 的真实 tags：

- `v1.0.62` → `10adc2475023e6b32493f8a14a1d7104f38d0852`
- `v1.0.63` → `b16aa84d11c250acdf644cd8b7812ab27d03dc6a`
- 返回修复提交：**`e4f38f4511f56c7128c46c0cda35e0570e3357da`（PR #272）**。

证据路径（均指对应 tag/commit，不是 Android 工作区现状）：

1. v1.0.62 `ui/screen/imports/ImportSheet.kt:274–280`：点击教务先 `onDismiss()`，再 `onJwImportRequested()`；旧 `ManagementPage` 也关闭 `showImportSheet`。
2. v1.0.63 改用 `AddTableScreen`。PR #272 的 `ui/nav/SleepyNavHost.kt` diff **删除 AddTable 路由启动 Activity 前的 `navigator.pop()`**；添加页留在返回栈中。
3. 同提交 `ui/screen/imports/ImportSheet.kt:141–153, 319–323`：记下 `jwImportLaunched`，表/课程数增长才触发 `onImported()`。`SleepyNavHost.kt:199–229` 将成功回调接到 `navigator.pop()`。

因此本次返回契约是：**从添加/导入方式入口进入教务，取消/系统返回保留原入口；导入成功才关闭该入口**。iOS 用明确成功结果代替观察条目计数，避免取消与已落库成功共用无参数回调。

另有独立语义变化：v1.0.63 `JwImportActivity.requestExit():211–217` 对非草稿直接退出；原始导入也不再自动建草稿。本切片按用户明确约束保留目标进度退出确认及草稿生命周期，不将这些更大流程变化混入返回修复。

核对命令：

```sh
git diff v1.0.62..v1.0.63 -- app/src/main/java/com/lingion/sleepy/ui/screen/imports/JwImportActivity.kt
git show e4f38f45 -- app/src/main/java/com/lingion/sleepy/ui/nav/SleepyNavHost.kt app/src/main/java/com/lingion/sleepy/ui/screen/imports/ImportSheet.kt
```

## 目标根因与最小原生接线

目标旧路径是 `ManagementPage → ImportSheet.onDismiss → AppRoot 延时 0.5 秒 → JwImportFlow`。入口已销毁，且成功/取消都只调用 `onFinish()`，无法恢复正确父页。

- `ImportSheet` 现在直接拥有教务 **原生子 sheet**；进入教务不关闭父 sheet，文本展开/输入状态保留。
- 草稿箱恢复先记录 id、关闭草稿箱，在草稿箱 `onDismiss` 后呈现教务，不在同一帧切换两个 presentation。
- `JwImportFlow.onFinish` 返回 `.cancelled` / `.completed`；已落库进入报告弹窗时就记录成功，避免报告期间退出被降级成取消。完成回调设一次性守卫。
- `JwImportReturnState` 在宿主 sheet `onDismiss` 消费成功：来自导入方式且成功才关闭父 sheet；取消/下滑保持父页；结果消费后清零，不污染下次导入。
- `AppRoot.pendingDraftId` 直接/外部恢复通道仍由根 sheet 承载，origin 为 `.direct`，成功/取消均不创建或打开导入方式页。原教务呈现 0.5 秒延时已删除。
- 进度退出 reducer、保存/删除草稿副作用、`isApplying` 退出闸、`onSheetDismissAttempt`、`interactiveDismissDisabled` 均保留。父/子 sheet 显式传递颜色和 palette，子 sheet 传递色彩模式；根 sheet 原 `SleepyThemeProvider` 保留。
- 纯策略类型放在现有 `JwImportFlow.swift` 中，避免引入需修改工程文件的编译单元。

## 实际验证

先读现有测试：

- `SleepyUITests/ManageImportUITests.swift:testJwImportEntryOpensSchoolSelect` 仅检查进入选校。
- `SleepyUITests/EducationalImportModalUITests.swift:43–83` 下滑后仅 `_ = waitForExistence`，未断言具体返回目标；搜索重置用例也没有重开后验证搜索内容。不能当作返回契约已通过。
- `SleepyUITests/UIElementAuditUITests.swift:testA4_ImportSheetNavigationBack` 覆盖导入方式直接返回管理页；深色用例覆盖选校和导入页主题。
- `SleepyTests/JwImportFlowTests.swift` 覆盖诊断文案，不覆盖导航。

新增 `scripts/tests/test_import_return_navigation.py`：

- **RED**：初始 5 项全部失败，捕获旧入口提前关闭、旧 timer、结果不区分及缺少返回策略。
- **GREEN**：最终 **6/6 通过**；两个 Swift 子进程串行执行。
- 实际执行生产返回策略：无成功事件下滑、取消、成功后 dismiss、重复消费、下一次取消、成功后迟到取消、direct 入口成功/取消。
- 实际执行原进度退出 reducer：无进度直接退出、有进度弹确认、继续保留进度、留草稿和删草稿结果。
- 源码接线检查：父 sheet 保留、草稿 dismiss 后恢复、成功/取消回调、直接入口分流、主题和交互关闭闸保留。
- 四文件 `swiftc -parse` 退出码 0；scoped `git diff --check` 通过。

```sh
python3 scripts/tests/test_import_return_navigation.py
swiftc -parse Sleepy/SleepyApp.swift \
  Sleepy/ui/screen/manage/ManagementPage.swift \
  Sleepy/ui/screen/imports/ImportSheet.swift \
  Sleepy/ui/screen/imports/JwImportFlow.swift
```

原有测试未修改；未运行 xcodebuild、模拟器、commit 或 push。parse 仅证明语法，不代表完整工程类型检查通过。

## Runtime 缺口 / 后续验收

目前不能宣称“100% native 等价已验收”。需在 iOS 15/16 真机或模拟器验证：

1. 管理页→导入方式→选校，按钮取消/下滑均返回同一个导入方式页，原粘贴输入仍在；再次进入选校为新搜索会话。
2. 草稿箱→恢复，箱子 dismiss 后教务只呈现一次；取消回原导入方式，保存/删除草稿后列表刷新。
3. 导入落库成功（包括成功报告弹窗）后先关教务、再关入口，停留管理页；不得短暂重开入口或丢失父页关闭事件。
4. 有进度时下滑触发确认；继续、留草稿、删草稿、写入期间禁止退出的真实交互。
5. 两层 sheet 在浅色、深色、自定义主题下的环境继承。
6. 外部 `pendingDraftId` 通道直接进入/退出，保持原页面；特别检查外部请求在其他 modal 已打开时的 UIKit 呈现行为。本仓库 `handleDeepLink` 当前只有文本 import URL，没有独立 draft URL 分支，本切片未虚构新的 URL 协议。

本切片只处理上述返回契约，不代表 Android v1.0.63 新添加课表/定向加课/课程勾选流程已整体迁移。parser、JwSchoolInfo、drag 与工程文件均未改。
