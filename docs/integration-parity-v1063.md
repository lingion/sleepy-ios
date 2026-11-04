# v1.0.63 集成准备：upstream 基线与 PR34 / PR35 净增量

## 交付状态

- 日期：2026-11-03。
- 分支：`integration/parity-v1063-all-prs`。
- 目录：`/Users/kerrylee/sleepy-ios/.worktrees/integration-parity-v1063`。
- HEAD：`6c9dec44dafaa0e683f94a4855f34fc5dc9483a5`，修改保留在工作区，未暂存、未 commit、未 push。
- `git ls-remote upstream refs/heads/master` 返回同一 SHA；创建前检查目标目录和分支均不存在。
- 检查仓库及祖先目录，未发现适用的 `AGENTS.md`。
- 第一轮做静态检查与 `swiftc -frontend -parse`；第二轮按追加委托修复接口并运行独立 macOS SwiftPM XCTest target，详见文末。没有运行主工程 `xcodebuild`、模拟器或共享 DerivedData 构建。
- 本 agent 未修改 `.worktrees/parity-v1063`。第一轮没有迁入 PR36/WIP；后续主 agent 与 header/hue agent 已向本目录追加集成切片，当前整棵工作树不能再按第一轮净增量认定，归属见文末。

本次另在仓库本地 `.git/info/exclude` 增加了 `/.worktrees/integration-parity-v1063/`，防止父工作区把该目录当作未跟踪文件加入。它属于 Git 本地元数据，不是提交内容。使用 `git worktree add` 是为了精确指定已批准的路径、分支和基线；原生创建工具仅接受名称，不能表达这三个约束。

## 基线内容与去重证据

| 来源 | 取舍与证据 |
| --- | --- |
| PR31 `0f0ebfa` | 已在 upstream。其 tree 与 PR35 的 `b248efd` 均为 `7541b5860b772eae131043c2f9929d42301ed7e1`；不重复迁移 v1062 大批功能。 |
| PR32 `0004c92` | 保留全部 parser 编译修复。六个文件为 `JwEcuplScriptParser`、`JwJsonParsers`、`JwNwpuPostParser`、`JwOldQzSuperParser`、`JwOldZfParser`、`JwWakeUpCompatParsers`。 |
| PR33 `6c9dec4` | 保留全部注释和资源清理。修改文件以此版本为底，未用旧文件整段覆盖。 |
| PR35 `6b3e848` | `b248efd..732f471` 中的 parser 修复由 PR32 的新版基线承接；本次 parser 零修改。 |
| PR35 `732f471` | 第一轮移植下述三文件净修复，曾验证代码等价；第二轮因接口断裂进一步修改，当前版本不再声称与该补丁逐代码等价。 |
| 重复补丁 `e7b1eab`、PR34 分支 `1556346` | 与 `732f471` 的稳定 patch-id 均为 `a95a44c955955ad3a02399b5dfcff623fefb713b`，只保留一份。 |

不要以 `upstream/master...feature/parity-v1062` 的三点差异判断剩余工作：squash 后 merge-base 偏旧，会把已经进入 PR31 的整批代码重新列出。这里使用 tree 等价与逐提交净补丁核对。

## 第一轮净增量记录（第二轮变更见文末）

### PR35：三个文件

1. `Sleepy/data/entity/CourseColorEntity.swift`
   - 增加可选 `rowid`、`didInsert(_:)` 回填和默认 `nil` 的初始化参数。
   - 保留 `(tableKey, groupId)` 复合主键；`rowid` 不加入 `CodingKeys` 或数据库编码。
   - 直接消费者是 `CourseColorDao.upsert` / `upsertAll` 的 `rowid` 返回值。不是一次 schema 迁移。
   - 与原补丁的文本差异仅为中文注释及空白整理，未复制冗余的编码注释。
2. `Sleepy/data/repository/ScheduleRepository.swift`
   - 删除第二处重复 `periodTableDao` 声明，保留顶部的注入属性与初始化。
   - `getAllGroupIds` 的无效 `.distinct(by:)` 改为原补丁中的稳定顺序去重。
   - 两处异步课程插入后的缓存失效切到 `await MainActor.run`。
   - PR33 的现有注释全部保留。
3. `Sleepy/util/CourseColorWriteGlue.swift`
   - 新组补色与全表重算的无效 `.distinct(by:)` 调用改为原补丁中的去重实现。
   - 两处成功写入后的缓存失效切到 `await MainActor.run`。
   - CLASSIC/空 anchor 的零写入、已有颜色跳过、写失败降级语义保持原状。

### PR34：按新版实现移植三个文件

4. `Sleepy/ui/screen/mine/ReminderScreen.swift`
   - 按 `180fbfb` 的意图移除 fluid 模式分段、实验标签、字段菜单、说明、状态、标签辅助函数及对应 `onChange`。
   - 保留真实横幅开关，直接读取/写入 `isBeforeClassBannerEnabled` / `setBeforeClassBannerEnabled`，变更后请求 `ReminderRescheduler`。这是当前通知调度器实际读取的偏好。
   - 文案使用基线已有的 `reminder_mode_banner` / `reminder_mode_banner_sub`。旧 PR 的 `reminder_banner_title` / `reminder_banner_sub` 在新版五种语言资源中均已不存在，不能照抄。
   - iOS 可用的三行可靠性诊断移到课前提醒块内，随课前提醒开启显示，不再依赖 fluid 状态。
   - 保留新版 `reminder_table_reminder_entry` 按钮及 `TableReminderScreen` sheet；入口、sheet、动态预览代码分别与基线逐字一致。
   - 保留通知授权流程、日期规则、节假日导航、每日/次日提醒、分钟输入、勿扰设置。
5. `Sleepy/util/AppPrefs.swift`
   - 按 PR34 对五个旧 fluid 访问器增加弃用标记，说明仅用于旧偏好迁移/同步。
   - 键名、默认值、方法体及手表快照读写语义均不改动，不清空用户数据，也不在进入页面时擅自开启横幅。
   - 未复制旧补丁中无法核实的审核日期和厂商归因。
6. `Sleepy/ui/screen/mine/CalendarImportDialog.swift`
   - 仅移植 `a7b4d09` 的一行：`transfersEnabled` 初值读取 `AppPrefs.shared.isCalendarApplyTransfers()`。
   - 保留新版 `await SystemCalendarManager.writableCalendars()` 和既有 `loadState` 逻辑。与旧 PR 整文件比较并不等价，这是有意保留 PR31 的异步日历加载。

第一轮源码合计 **6 文件，41 行新增、144 行删除**。这不是第二轮最终统计；第二轮新增 DAO 修复及回归验证文件。

## 明确排除的历史内容

- PR34 旧历史中的 14 个 worktree gitlink；新基线树中没有 gitlink，也没有添加任何 gitlink。
- 空的 `SleepyUITests/AppStoreScreenshotTests.swift`。
- `ANDROID_FEATURE_AUDIT.md`、`ANDROID_FEATURE_FIX_PLAN.md`、`ANDROID_FEATURE_FIX_SUMMARY.md`：旧审计结论未直接复制，本说明记录实际取舍。
- 历史截图、截图脚本、`docs/widget-glass-preview.html`、旧商店文案等附带产物。
- PR35 已由 PR31/PR32 承接的功能与 parser 改动。
- PR36、native drag 与主 agent 活跃 worktree 的任何未提交内容。

现有 `SleepyTests` / `SleepyUITests` 没有删改、置空或跳过。

## 第一轮验证与自审记录

1. 第一轮：逐项对照 PR35 补丁、PR34 原意和新版调用链。确认 `CourseColorDao` 使用插入后的 rowid、缓存为 `@MainActor`；发现 mode 接口缺口和旧文案键失效，改为真实横幅偏好与现有文案键。
2. 第二轮：独立 Python 静态断言通过，覆盖三文件与 PR35 的去注释/空白代码等价、AppPrefs 去掉五个弃用标记后代码等价、日历弹窗严格一行差异、课表提醒入口/sheet/预览逐字保留、fluid UI 引用消失、五语言横幅键存在、parser/资源/测试不变、无 gitlink、索引未暂存及 HEAD/分支固定。
3. `xcrun swiftc -frontend -parse` 对全部六个源码文件执行成功；`git diff --check` 成功。
4. 静态核对曾将日历文件误设为与旧 PR 整文件代码等价，断言失败后定位到 upstream 已有的异步加载差异；验证改为“基线 + 一行初值修复”，没有回退上游代码。

可复跑的语法与差异检查（在本 worktree）：

```sh
git diff --check
xcrun swiftc -frontend -parse \
  Sleepy/data/entity/CourseColorEntity.swift \
  Sleepy/data/repository/ScheduleRepository.swift \
  Sleepy/util/CourseColorWriteGlue.swift \
  Sleepy/ui/screen/mine/ReminderScreen.swift \
  Sleepy/ui/screen/mine/CalendarImportDialog.swift \
  Sleepy/util/AppPrefs.swift
git diff --stat
git status --short
```

`-parse` 只证明语法可解析，不解析依赖、不证明类型检查通过。第一轮未执行 XCTest；第二轮已执行下面记录的独立 XCTest，但仍不能称本分支满足全工程可编译/可发布条件。

## 主 agent 后续复核项

1. **mode 接口缺口已在第二轮修复。** 请重点复核文末的 iOS 横幅投递闸兼容决策；原有六个模式测试未修改且已通过独立 target。
2. **配色胶水接口缺口已在第二轮修复。** 同步、async 兼容及事务内调用均已接通；需在最终工程继续验证完整课程导入/撤回链，而非仅颜色表事务。
3. 日历 `loadState` 已会读取保存值并在无保存值时回退 true，因此 PR34 一行初值修复的实际影响仅在首次状态加载前；基线 `isCalendarApplyTransfers` 默认语义需与最终 v1063 再核对。
4. 在主 agent 的隔离构建环境执行相关测试：配色写入/迁移、导入、提醒偏好/课表提醒、通知调度及手表同步；验证弃用标记在项目警告策略下不会阻断构建。
5. 真机/模拟器检查：提醒页面无 fluid 入口，横幅开关能恢复之前关闭的投递，课表提醒入口可进入且每表设置落盘，可靠性诊断可见，日历调休开关重开保持保存值。
6. 本次没有 commit，迁移时应审阅并搬运工作区 diff（含本未跟踪文档），不能只 cherry-pick 此分支的 HEAD，否则只会得到原始 upstream 基线。

## 第二轮：缺失接口修复与验证

### 调用链与依据

- 对照原有 `BeforeClassModePrefsTests` 全六例及 `CourseColorWriteGlueTests` 全 25 例，未修改原测试文件。
- 对照历史 `d547c0b` 的模式接口、`96164fa` 的同步配色胶水和事务内写法，以及本地 Android `app/src/main/java/com/lingion/sleepy/util/{AppPrefs,CourseColorWriteGlue}.kt`。
- 读完真实调用点：`ScheduleRepository` 单课插入、批量插入和覆盖导入；`NewTableImport` / `JwImportViewModel` 的数据库事务；`AppearanceScreen` 的 async 重算；`WatchSyncSnapshot` 的 banner → fluid 恢复顺序；`NotificationScheduler` 的横幅投递闸。
- GRDB `afterNextTransaction` / `inSavepoint` 依据本地锁定依赖源码；该依赖只读复用，构建产物写独立临时目录。

### 模式兼容

新增 `KEY_BEFORE_CLASS_MODE = "before_class_mode"`、`BEFORE_CLASS_MODE_BANNER = "banner"`、`BEFORE_CLASS_MODE_FLUID = "fluid"` 及 getter/setter：显式模式优先，未写模式时按旧 fluid 键推导；读取不主动迁移或擦除键。

**相对旧 B3 分支的一处有意差异：** iOS 已移除 fluid UI，仍保留可开关的真实横幅。因此 `isBeforeClassBannerEnabled()` = 模式为 banner **且**旧 `before_class_banner` 投递闸为 true（未写默认 true）。`setBeforeClassBannerEnabled(false)` 只关投递，不改模式；true 写投递闸并选择 banner。fluid 兼容 setter 仅写模式，不打开横幅投递闸。这样同时满足：

- 原测试的 fluid 迁移、模式往返、banner=false 不覆盖 fluid 的约束。
- UI 关闭横幅后调度器真实停发；重新开启可从历史 fluid 状态恢复。
- 旧 `banner=false` 保存值不丢失；手表按 banner=false → fluid=false 恢复时不会意外重开横幅。

没有恢复 fluid UI，没有新增后台服务或伪造实况卡片实现。五个兼容访问器仍保留第一轮弃用标记。

### 配色接口与事务契约

| 接口 | 当前行为 |
| --- | --- |
| `persistNewGroupHues(dao:entities:prefs:)` | 同步、prefs 默认 `.shared`；返回前完成读取、规划和事务写入。 |
| `persistNewGroupHues(mode:anchor:dao:entities:) async` | 保留显式参数 async 调用契约，复用同一个同步事务核心，返回前写入完成。 |
| `persistNewGroupHuesInDb(dbw:dao:entities:prefs:)` | 同步复用调用方句柄，能看到未提交旧色；绝不重入 writer。返回成功规划仍受外层提交/回滚控制。 |
| `recalcWithAnchor(anchor:dao:gids:)` | 恢复既有测试要求的同步返回；nil 零写，0° 合法；失败返回空而非假装规划已写入。 |
| `recalcAll(dao:gids:prefs:)` | 同步偏好注入入口，主题/种子及缓存刷新使用同一 mode。 |
| `recalcAll(mode:dao:gids:) async` | 保留外观页 async 入口，共用同步重算核心。 |

- `CourseColorDao` 增加 `getHueMapInDb` / `upsertAllInDb`，原非事务接口复用它们。
- `CourseColorEntity.globalTableKey` 补为 `GLOBAL_TABLE_KEY` 的同源别名，供现有测试及历史同步调用者使用。
- 新组补色把“读旧色 → 规划 → 写入”放在同一写事务，已存在 hue 不动；读取错误不当作空表。
- 写批次用 savepoint：第二条写入失败时撤回该批所有颜色，返回 `[:]`；课程导入事务仍能继续。颜色是增值数据，这是 Android `runCatching → emptyMap` 的既有错误降级契约，不是后台 fire-and-forget。
- 只在外层事务成功提交后调度 MainActor 缓存刷新；外层回滚不发布该批缓存。只有缓存刷新异步，数据库写入不放进 Task。
- `ScheduleRepository.insertCourse` 改为返回前同步补色；`insertCourses` 删除原来重复的后台补色 Task，保留一次同步调用；调用 `onDataChanged` 前已经完成补色。
- 复用 `CourseColorUtil.isNotBlank` 并按首次出现顺序去重；不 trim 非空 groupId，以免改变课程身份。CLASSIC/空 anchor 不进入颜色写事务。

### 独立验证 target

新增：

- `SleepyTests/ParityInterfaceCompatibilityTests.swift`：8 例，覆盖横幅关闭/恢复及手表恢复顺序、存量偏好、同步落盘与注入种子、事务内可见性/外层回滚、批次写失败局部撤回、读失败不覆盖旧色、重算失败返回空、async 返回前落盘。
- `SleepyTests/CourseColorCommitBoundaryTests.swift`：1 例，验证注入模式下重算成功提交后缓存实际读到新值。
- `scripts/parity-interface-check/run.py` 与 `Support.swift`：临时生成独立 macOS SwiftPM target，拷贝生产 `AppPrefs`、`CourseColorUtil`、`CourseColorWriteGlue`、`CourseHueStore`、`CourseEntity`、`CourseColorEntity`、`CourseColorDao` 七个完整文件。

target 使用真实 GRDB/SQLite；只建 `course_colors` 表。UIKit 颜色桥使用 macOS NSColor；主题、节假日、时间格式等无关边界用显式适配层。原配色测试文件完整复制；从原提醒测试文件原样选取 `BeforeClassModePrefsTests` 类，另一 `TableReminderEnabledRepoTests` 类不在本 target 范围内，原工程中仍完整保留。

运行约束：`swift test --jobs 1 -Xswiftc -j1`、`nice -n 15`，离线依赖路径；不运行 xcodebuild、模拟器或共享 DerivedData。首次 GRDB 冷编译触及 120 秒工具超时，随后延长命令超时、继续单 job 增量构建，没有增加并行度。

**RED → GREEN 证据：**

1. 修复前先添加回归和 target：编译 RED，报告 `CourseColorEntity` 缺少 `globalTableKey`，事务内调用表达式也无法完成诊断。
2. 接通接口后，原 6 + 25 个测试及新增 8 个测试共 39 例通过。
3. 自审发现重算的缓存刷新仍读取全局 mode，新增提交边界测试获得行为 RED：数据库已有颜色，但缓存为空、刷新期望超时。
4. 将注入 mode 传到重算核心及提交回调后，**40 个 XCTest 全部通过，0 failures**。未削弱或改动任何已存在的测试。

日志位于 `/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/`：

- `parity-interface-red.log`
- `parity-interface-cache-red.log`
- `parity-interface-green.log`

复跑：

```sh
PARITY_CHECK_DIR='/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/parity-interface-check' \
GRDB_SOURCE='/Users/kerrylee/sleepy-ios/build/sim-dd/SourcePackages/checkouts/GRDB.swift' \
nice -n 15 python3 scripts/parity-interface-check/run.py
```

### 验证边界与并行改动

- 40 例是独立目标结果，不是完整 iOS XCTest 结果。真实主题生成/系统颜色、全量数据库迁移、通知授权/投递、UI、手表传输、课程库事务整链仍须主 agent 在允许构建后复核。
- 本轮未重新生成 Xcode 工程；新增 XCTest 文件已在独立目标执行，最终工程仍需按既有 XcodeGen 流程纳入文件后执行。
- `ScheduleRepository`、`NewTableImport`、`JwImportViewModel` 的调用点经源码核对和语法解析；独立目标没有编译完整 Repository/ViewModel 依赖图。
- 原有已跟踪测试文件和 parser 源码未修改。本 agent 未迁入 PR36/WIP；并行会话已修改五语言 `Localizable.strings`、`CourseTableView`、`HueSlider`、`PeriodHeaderCellContent`、`AppearanceScreen`、`CourseColorSection`、`LicenseScreen`、`PeriodHeaderSettingsScreen`、`ScheduleDisplayScreen`，并新增 `CourseOccurrenceIdentity.swift`、`CourseOccurrenceIdentityTests.swift`、`docs/header-hue-integration.md` 与 `scripts/tests/`。这些改动已保留，不计入本 agent 接口修复归属，也不在本 target 验证范围。
- 第二轮本 agent 的生产变更归属为 `AppPrefs.swift`、`CourseColorWriteGlue.swift`、`CourseColorDao.swift`、`CourseColorEntity.swift`、`ScheduleRepository.swift`；其余第一轮 UI 修改继续保留。

## 第三轮：header/hue 集成依赖交接

按主 agent 追加委托，在 `AppPrefs.swift` 节次表头设置区逐字迁入源 `.worktrees/parity-v1063/Sleepy/util/AppPrefs.swift` 的三个符号，未整文件覆盖：

- `KEY_PERIOD_HEADER_TIME_ALIGNMENT = "period_header_time_alignment"`。
- `getPeriodHeaderTimeAlignment()`：默认 `dash`；仅 `center` 返回 `center`，非法存量值回落 `dash`，读取不改写存储。
- `setPeriodHeaderTimeAlignment(_:)`：仅接受 `dash` / `center`，用源实现的 `precondition` 拒绝非法入参（触发前置条件失败，不是静默 no-op），校验后写入 `sp()`。

默认 `sp()` 与 UI 的 `@AppStorage(..., store: .standard)` 同源；测试注入 UserDefaults suite 时，读写均保持在注入 suite 内。真实调用点为 `PeriodHeaderSettingsScreen`、`PeriodHeaderCellContent`、`CourseTableView`，本轮未改这些 UI 文件。五语言由主 agent 提供，拖课 repository 函数由主 agent 后续接入。

新增 `PeriodHeaderTimeAlignmentPrefsTests.swift` 三例：默认读取无副作用、合法值持久化与实例重建、非法存量回落且不改写。先获得缺失符号的编译 RED，再补入三个符号。

**最新独立验证：2026-11-03 21:29:15，43 个 XCTest，0 failures**（第二轮 40 + 本轮 3）。采用 `nice -n 19`、单 job、已有离线 GRDB 增量构建。日志为上述临时目录下 `parity-header-red.log` / `parity-header-green.log`；此前两组 RED/GREEN 日志保留。

附加校验通过：三个符号所在块与源 parity-v1063 完全一致；七个生产文件及四个完整测试文件与本次验证 target 副本逐字节一致；原有已跟踪测试与 parser 未变；两个课程插入路径均在 `onDataChanged` 前执行一次同步补色；HEAD/分支不变、暂存区为空。

非法 setter 的进程终止行为未单独启动崩溃子进程测试，仅核对与源实现完全一致及前置条件位于写入之前。完整 iOS 类型检查、原生 UI、通知/手表运行链仍未验证。用户报告主机 load 359 / 125MB free、原生 UI 无法启动；遵守限制，本轮没有运行 xcodebuild 或模拟器。全部修改未 commit/push。
