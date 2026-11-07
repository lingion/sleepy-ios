# PR #34 / #35 / #36 集成覆盖独立核对

# PR #34 / #35 / #36 集成覆盖独立核对

## 结论

固定于下述 Git 对象的静态核对发现 **3 项可操作缺口**，已于 `67fd630` 全部修复：

1. **[P1] ECUPL 八参数活动捕获组** - `140c6d4` 已修复，与 PR #35 `2c85864` 保持一致
2. **[P2] URP 奇偶段测试契约** - `67fd630` 已修复，三处断言更新为保留最后一周
3. **[P3] 三行表头 hanging 滑杆基线** - `1bacc6d` 已修复，使用 `NativeBaselineSlider` 并捕获进页基线

本轮只写本报告。未 checkout、merge、改生产代码或测试、运行本地编译/测试/模拟器，也未派代理。**没有 CI 通过结论**；以下"覆盖"仅指静态补丁与调用链证据。

---

## 修复记录（2026-11-05）

以下三项缺口已由主会话修复并提交至 `integration/parity-v1063-all-prs`：

### ✅ [P1] ECUPL 正则捕获组修复 (`140c6d4`)

- 承接 PR #35 `2c85864`，参数 1/3/5 改用非捕获组 `(?:…)`
- 保留五个语义捕获组：g1 教师、g2 课名、g3 教室、g4 日期、g5 位图
- 现有测试 `JwEcuplScriptParserTests.swift:68–138` 覆盖

### ✅ [P2] URP 测试契约更新 (`67fd630`)

- `JwNewUrpParserTests.swift:35` - endWeek 1→3
- `:47` - endWeek 2→4
- `:59–61` - `[(1,1,1),(6,6,2)]` → `[(1,3,1),(6,8,2)]`
- 生产代码（PR #36）已正确保留最后一周，测试同步修正预期
- 用户授权："随便改 只要事半功倍就行"

### ✅ [P3] 三行表头 hanging 滑杆基线 (`1bacc6d`)

- 使用 `NativeBaselineSlider` 替代标准 `Slider`
- 添加 `@State private var baselineHanging: Float?` 和 `captureBaselines()`
- `.onAppear` 捕获进页基线，保留原有 0.1 量化和实时预览

---

## 1. 可操作缺口（已全部修复）

### [P1] 恢复 ECUPL 八参数活动的五个语义捕获组

- **定位：`Sleepy/data/jw/JwEcuplScriptParser.swift:43–44`。**
- 上游修复：PR #35 `2c85864`，在最新 head `c69d525` 中仍有效。
- integration 的正则为八个参数分别建立捕获组，但消费端 `:100–113` 仍按五个语义组读取：g1 教师、g2 课名、g3 教室、g4 日期、g5 位图。上游已将第 1、3、5 个原始参数改为非捕获文本，只保留这五个语义组。
- 现有 `SleepyTests/resources/ecupl_script_sample.html:17` 输入：

  ```javascript
  newActivity("C001","张教授","x","民法(总则)","x","明法楼A101","2024-02-26",65535);
  ```

  integration 中 g4 为 `民法(总则)`，`parseIsoDate(m.group(4))` 返回 nil，随后 `continue`；其他正常课程也在同一位置被跳过。即使只挪动日期读取索引，姓名/教室/位图仍会错位，必须统一捕获与消费契约。
- 已有保护断言：`SleepyTests/JwEcuplScriptParserTests.swift:68–84` 要求输出四个课时并验证课名/教师/教室，`:89–96` 要求 super fixture 三门课，`:130–138` 覆盖 classic 路由及空教室。首项在 count 断言之后直接取 `courses[0]`，空结果还可能造成测试进程越界退出。这里是源码推导，未执行这些测试。
- 建议承接 `2c85864` 的正则语义修复，保留这些现有断言；由主会话 CI 验证。不是新增协议或另写一套 parser。

### [P2] 承接 URP 双元素隔周段的测试契约修正

- **定位：`SleepyTests/JwNewUrpParserTests.swift:35`、`:47`、`:59–61`。**
- 上游修复：PR #35 最新提交 `c69d525`。
- integration 的生产代码 `Sleepy/data/jw/JwNewUrpParser.swift:211–218` 已在 stride-2 循环前设置 `end = weeks[k]`，正确保留两个元素的末周；生产修复已覆盖，不能再把它描述为“解析器漏周”。
- 测试却仍要求 `[1,3] → (1,1,1)`、`[2,4] → (2,2,2)`、`[1,3,6,8] → [(1,1,1),(6,6,2)]`。正确输出应分别为 `(1,3,1)`、`(2,4,2)`、`[(1,3,1),(6,8,2)]`。三个旧断言与当前生产实现直接冲突，会阻断执行到这些用例的测试验收。
- 上游还增加 `assertWeeksMatchBitmap`，将输出范围按 type 展开后与输入位图逐周比较，约束不能缺失、重复或新增周次。integration 尚无这项断言。
- 建议按上游 `c69d525` 的独立测试修正承接，说明这是纠正过时预期；不要为了旧断言改回会丢末周的生产逻辑。本报告没有修改测试或声称观测到 CI 失败。

### [P3] 补齐三行式表头悬挂滑杆的进页基线

- **定位：`Sleepy/ui/screen/mine/PeriodHeaderSettingsScreen.swift:112–120`。**
- 上游功能：PR #36 `db22842`，最新 head `c9de09a` 仍包含 `baselineHanging`、进入页面捕获及偏离超过 0.05 后显示基线标记的逻辑。
- integration 在 `layout == "three_line"` 时仍直接渲染普通 `Slider`，仅维护当前 `hangingUnits` 并写偏好，没有保存进入页面时的值，也没有基线视图。用户拖动悬挂量后无法看到原位置。
- **这是该悬挂滑杆的局部遗漏，不是原生滑杆整体缺失。** `ScheduleDisplayScreen.swift:117–124,175–178` 的网格缩放、周缩放、圆角、stack/rail/fold 六滑杆已经通过 `NativeBaselineSlider` 实现固定基线；`HueSlider` 也已有 Float 基线。`docs/header-hue-integration.md:11,54` 的六滑杆迁移范围与此一致。
- 建议复用现有原生基线组件并只捕获一次页面初值，保持当前范围 `-1...1`、0.1 量化和偏好提交语义。无需恢复上游固定 11pt 内缩的近似几何。

## 2. 证据时点与比较方法

上游 PR head 最终查询：**2026-11-04 14:17 UTC / 22:17 UTC+8**。三个 PR 均 open，base 为 `master`；当时查询的 base SHA 为 `0f0ebfadc550cbe2d7ae466a0f4648da7f48bdc7`。下表覆盖矩阵及提交计数以 `1e4fbec` 为全量审查基线；另于 **14:21:56 UTC / 22:21:56 UTC+8** 增量复核至 `326cc8f50c1224a9cb44a51b1b25b334ba20d881`。

| 对象 | 本轮固定 SHA | 与 integration 的 merge-base | integration 不可达的提交数 |
| --- | --- | --- | --- |
| integration/parity-v1063-all-prs（全量基线） | `1e4fbec1f398892e3490a3eead5b9f975e4fbfa8` | — | — |
| PR #34 | `7301d6c425c6150cc77ed579ca740b9ea9e3e958` | `72c822c35a62f449c0f2b8e29bddde8713da2378` | 12 |
| PR #35 | `c69d5253aaef76d81ea40c1a33676b7ca8da546c` | `39f85b2280da492bccd50b0bdb518225e53cfbd2` | 41 非 merge + 7 merge |
| PR #36 | `c9de09a4e21d395ecd9a7f6379d8638f5b3015d6` | `72c822c35a62f449c0f2b8e29bddde8713da2378` | 11 |

- 用 `gh api repos/lingion/sleepy-ios/pulls/{34,35,36}` 固定并复查 head。GitHub compare 对本地 integration SHA 返回 404，因此通过 `git fetch --no-write-fetch-head origin <heads>` 获取对象后只读比较，未切换分支或合并。
- 用 `git log integration..head`、`git merge-base`、`git cherry` 建立独有提交清单；所有独有非 merge 提交的 patch-id 检查都是 `+`，**这不能证明功能遗漏**。
- 检查各 PR 从 merge-base 到 head 的有效最终补丁，再在这些路径内比较 `git diff <PR-head> <integration>`，读取替代实现、调用点及现有测试。大量差异是注释中 `Android` 的改写；已将其与可执行差异区分。
- PR #35 的生产/测试/脚本筛选路径中，36 个最终 blob 与 integration 完全相同，118 个不同；不同包括注释、替代实现、新功能和下文明确缺口，不能当成 118 项漏迁。
- 报告行号均按 `1e4fbec` 的 Git blob。主会话随后提交 `1f7809c`（debug）与 `326cc8f`（theme）；本轮读取两提交中涉及 PR 消费链的增量，确认 Float 色相状态、配色事务写入、周视图日期显示、目录准入路径仍保留，widget 仍使用 `effectiveWidgetIsDark`。这不是对 theme/debug 新能力的全面审计。
- 第 1 节涉及的五个文件（ECUPL parser/tests、URP parser/tests、`PeriodHeaderSettingsScreen`）在 `1e4fbec` 与 `326cc8f` 的 blob 完全一致，三项缺口及定位在该增量终点仍成立。共享工作树的其他修改属于主会话，不用于证明已提交覆盖。

## 3. PR #34 有效补丁覆盖

| 上游提交 | 核对结果与 integration 证据 |
| --- | --- |
| `180fbfb` 移除 vivo 流体 UI | 已覆盖。`ReminderScreen.swift:54–58,407–420` 使用 banner 开关，没有 fluid 分段或字段配置 UI；`AppPrefs` 旧 fluid 访问器仅保留迁移/同步兼容并标记 deprecated。PR #35 的 fluid UI 不应重新带回。 |
| `a7b4d09` 日历读取保存的调休选项 | 已覆盖。`CalendarImportDialog.swift` 的 `transfersEnabled` 从 `AppPrefs.shared.isCalendarApplyTransfers()` 初始化，不是常量 false。 |
| `1556346` 三处编译接口修复 | 有静态等价接口。`CourseColorEntity` 提供初始化入口，repository 配色写入口已改用现有同步胶水；未将接口存在升级为整工程编译成功。 |
| `4f019e6` CI 失败传播/模拟器 | 已替代。`.github/workflows/ios-build.yml:72–113` 动态选择 available iPhone UDID，build/test 均 `set -euo pipefail`，测试输出管道保留失败状态；acceptance timeout 为 120 分钟。 |
| `8e39034` Float 色相状态 | 已替代。`AppearanceScreen.swift:30,132–142,226–230` 持有 `HueEditingSession`，后者在 `HueSlider.swift:14–18` 明确为 `Float current/baseline`，提交也是 Float。不能因没有同名 `seedHue` 状态误报。 |
| `6e8e7a6`、`7301d6c` 四语言转义/星期回归保护 | 已覆盖其静态修复。en/es/ja/zh-Hant 的十个配色资源行与修复后的内容一致，未发现行首外层 `\"` 键；`scripts/tests/test_weekday_lookup.py` blob 相同。未运行 Foundation 字符串加载或脚本。 |
| `e9659af` / `ab2bc77` 固定时区方案 | 后一提交已撤回前一提交；不把被撤回的固定时区算作缺口。 |
| `648e712` / `27b936b` 同城排序方案 | 后一提交已撤回前一提交，恢复协议完整度参与排序的契约；不要求 integration 承接被撤回的排序。 |
| `c68dc37` 审计文档 | 属说明性提交，无新增运行功能。 |

附带工具差异：`a7b4d09` 还夹带新增 `scripts/appstore-shot.sh`、`scripts/appstore-shot-watch.sh` 和空的 `SleepyUITests/AppStoreScreenshotTests.swift`；integration 未包含这两个本机截图脚本及空文件。脚本依赖硬编码本机模拟器/构建路径，不是上述产品修复的调用链，本轮不把它们算作产品缺陷，也不宣称已经等价迁入。工作树指针和其他说明文档不作为运行功能覆盖证据。

## 4. PR #35 功能簇与后续修复覆盖

| 上游提交/功能簇 | 核对结果与证据 |
| --- | --- |
| `7bd9214`、`96164fa`、`c5da446` 持久色相/安全弧/写侧/外观入口 | 已覆盖并重组。`CourseColorDao`、`CourseColorUtil`、`CourseHueStore`、`ImportRoster`、`WatchSyncSnapshot` 承载持久色相与同步；`AppearanceScreen` 调用独立 `CourseColorSection`，真实课程预览复用首页配色优先级。 |
| `b80054c`、`da41beb`、`61a1738` 配色事务及契约 | 已替代。`CourseColorWriteGlue` 在同一写事务读取/规划，以 savepoint 回滚失败配色，在 commit 后失效缓存；`NewTableImport.swift:98` 与 `JwImportViewModel` 的导入事务调用该入口。上游 `CourseColorTransactionTests.swift` 文件虽不存在，`ParityInterfaceCompatibilityTests.swift:61–98` 已覆盖未提交 hue 可见、外层回滚及第二行配色失败不回滚主导入，不能按缺文件判漏。 |
| `954ecc3`、`0e4043d` 色相 Float/配色容器重名 | 已替代。Float session 和独立配色组件的真实调用见第 3 节，不存在上游旧私有容器遮蔽该组件的路径。 |
| `6463345` 手表配色缓存调用 | 已覆盖。`SleepyWatchApp` 首载和 `WatchStore` 应用同步后的 invalidate 都传 `mode` 与 `dao`；widget 加载路径也刷新同一色库。 |
| `21c7c7c` widget 跟随系统深浅 | `WidgetLoader` 对该修复的有效代码已覆盖；没有因 system 模式无条件固定浅色的旧补丁回退。增量复核至 `326cc8f` 时，widget 视图仍通过 `effectiveWidgetIsDark` 处理系统深浅；未验收新 theme 的全部运行行为。 |
| `cf09fe8` SCAU/ECUPL/UMOOC/YL；`867b814` 七个解析器与 JZ/Kingo super | 注册、解析实现和路由存在；对 PR 修改的教务文件比较可执行差异后，明确遗漏是第 1.1 项 ECUPL 正则。Kingo 已被 PR #36 的集成版替代；其余所见差异为访问控制等价修复、静态调用修正或新增 jw_home/sg_asset。 |
| `2d6867f`、`7e5d5d1`、`0841901` 目录/搜索/域名/未验证准入 | 已覆盖并承接 v1063 目录。`JwSchoolInfo.swift:43–57` 包含 `isUnverified`、`grad_unverified` 和 parser/URL 准入；`SchoolSelectScreen` 保留目录身份与多候选匹配；`JwImportFlow.swift:158–159` 做未验证确认。详情见第 5 节。 |
| `0cd1a8a` 导入成功报告与 QQ 回路 | 已覆盖。`JwImportFlow.swift:409–440,764–765,955–956` 将未验证学校的成功导入转为报告弹窗，保留复制/群跳转路径；`JwImportReport.swift` blob 相同。 |
| `2f78681` 加课时段删除稳定身份 | 已覆盖。`AddCourseScreen` 仍以 block UUID 为 `ForEach` 身份，通过 ID 寻址绑定/删除；integration 的定日课程与快捷加课扩展没有恢复旧 index 绑定。 |
| `6f5bb0b` 预览稳定 ID 与页内确认 | 对应预览组件有效实现保留；`ImportSheet`/`JwImportFlow` 的区别主要为原生 sheet 返回状态与 WakeUP 口令入口，不是恢复两层确认 sheet 的旧路径。 |
| `d547c0b`、`c24c234` 提醒模式/每表提醒 | 每表提醒页面、repository 写入与重排存在；旧 fluid 键推导和 banner true 桥仍在。banner 可关闭由 integration 显式偏好实现，配合 PR #34 去除 unsupported fluid UI；`ParityInterfaceCompatibilityTests.swift:27–49` 有对应契约。 |
| `75009de` 旧通知数据源兼容 | integration 没保留上游 extension 的 `effectiveDayOfWeek` 桥，而是将仓内实现与测试替身统一改为 `courseDateForDate`。`NotificationSchedulerTests` 的 dayMapping 显式映射回同周日期，生产源返回完整调休源日；没有残留只实现旧签名的仓内 conformer，因此不按缺桥误报。 |
| `e26183f` 每日议程/深链/渲染口径 | 对应聚合与深链实现保留；课前调休循环按源日取周次，integration 额外以自然日处理定日课程。`NotificationScheduler.swift:583–605` 的扩展不是退回仅映射星期的旧逻辑。 |
| `b091780` widget 设置/画廊/hideTime | 独立设置与画廊保留；hideTime 在 `PeriodHeaderCellContent`、预览和真实网格宽度路径中接通，并与 v1063 的时间对齐设置合并。 |
| `11e8043` 隐私政策/小爱导出/日历调休/License | 有效入口与解析/导出代码保留；License 差异为可见文案和来源链接调整。日历事件内容跟源日、显示跟目标日的逻辑由 `CourseOccurrences` 扩展承接。 |
| `adada91` 提前调休不能截短学期 | 已覆盖。`SystemCalendarManager.swift:212–213` 仍以 `max(semesterEnd, …target+1…)` 算 effectiveEnd；日期计算已改用 `CourseOccurrences.calendar`，不能按不同表达式判漏。 |
| `d81d42e` 新建课表原子导入/草稿/smartConfig | `NewTableImport` 等原子编排实现保留；差异涉及 integration 扩展，不是回退为分散写入。 |
| `9dcef4e`、`e556d25` 结构锚点及 ECUPL/Kingo fixtures | findAnchors 和 fixture/测试存在；ECUPL 已有测试并不代表修复已覆盖，实际缺口见第 1.1 项。 |
| `130b942` 周视图日期参数 | 已替代。`CourseTableView.swift:1134–1143,1170–1172` 计算 `dayDates` 并传递到 DetailPanel/DetailDayColumn/DetailDayCard，未因删除 `showDate` 子参数而丢失日期显示。 |
| `6b3e848`、`732f471`、`4c82635` 初始化器/Swift API 修复 | 可执行差异核对包含 MatchHit 访问级别、`.array().first` 属性、静态方法限定与配色入口，存在等价实现；仅作源码契约核对。 |
| `cae82a3` WebView 测试服务并发连接 | 对应测试实现保留，没有恢复预连接占位阻塞的单连接处理。 |
| `6b60021`、`9e65df8` CI；`a9694c4`、`b248efd` 工程生成 | CI 由动态设备选择与独立 acceptance job 承接；`project.yml` 为生成输入并包含整个测试源目录，工作流生成工程后保存 artifact。不要求生成工程逐字相同。 |
| `0964443` 四语言转义 | 同第 3 节，静态修复已覆盖。 |
| `2c85864`、`c69d525` | **未覆盖项分别见第 1.1、1.2 节。** |
| `b67374f` 及 7 个 merge 提交 | 文档与合并历史已纳入最终树范围；没有以 merge SHA 不在祖先中另列功能缺口。 |

## 5. PR #36 覆盖及易误报项

| 上游提交 | 核对结果 |
| --- | --- |
| `f95ee1e` 目录迁移 | PR #35、PR #36 和 integration 均 4140 条；按 catalogId 比较 PR #36 与 integration 无新增/缺失身份，完整记录仅三校不同：南开 `enableFetch`、NBCC `status/enableFetch`、佳木斯 `status/enableFetch`。其余 4137 条记录一致。 |
| `db22842` 滑杆/表头设置 | 六个课表显示滑杆已有原生基线替代且重复 onAppear 不重置基线；色相基线存在。**只有三行式悬挂滑杆缺口见第 1.3 节。** |
| `19d25ac`、`b023ec0` 表头对齐渲染 | 已替代并贯通。`PeriodHeaderSettingsScreen` 显式传 centerTime 预览；`PeriodHeaderCellContent.swift:72–84,225–252` 分支渲染；`legacyTimeColumnPx` 统一宽度/列轴；`CardsGridView` 订阅偏好并将隐藏时间计入列宽。不是仅有设置项而未消费。 |
| `810b918`、`a38093b` Kingo 星期偏移/无教室/br 切分 | 已在原 `parseKingoSuperHtml` 中承接，无需另一同名/新函数。`JwWakeUpCompatParsers.swift:1244–1303` 识别 5/7 天表头、从右端对齐星期、动态寻找时间行、允许空教室、处理 compact 与 `<br[^>]*>`；并避免课名含“周一”时被误跳过。 |
| `6d5bdbd` 五语言表头文案 | 五语言中均有 alignment、dash、center 三键，设置页真实引用这些键。 |
| `8686521`、`c9de09a` seed 状态/Float | `HueEditingSession.current/baseline: Float` 至 `HueSlider`、seed commit 全链路覆盖；状态变量改名不是遗漏。 |
| `e7b1eab`、`478ec12` 编译接口/CI | 与第 3、4 节等价实现相同；没有静态接口缺失证据，未编译验收。 |

三校状态差异为已有明确裁决，不作为盲目漏迁：`docs/catalog-v1063-integration-audit.md:93–142` 记录南开/NBCC 在 iOS 尚缺专用自动抓取链，NBCC 已迁移 `classic_eams` 协议纠错但保留未验证；佳木斯先承接 Kingo 修复，再凭 iOS 验证决定转正。当前 Kingo 代码已经承接，状态保守保留不能反推 parser 遗漏。

未验证标签的准确口径：`SchoolSelectScreen.swift:707–714` 明确 supported/unverified 都不显示行徽章；这是源设计，非标签漏接。未验证风险提示走点击准入确认及成功后的导入报告；`JwSchoolInfo.isUnverified` 与 `isGrad` 已涵盖 `grad_unverified`。目录总数和候选 URL 存在不等于真实登录导入验证。

## 6. 后续验收边界

1. ~~主会话优先处理 ECUPL 正则和 URP 测试契约，再由线上 CI 验证对应测试；悬挂滑杆基线是独立低优先级 UI 缺口。~~ **已完成** - 所有三项缺口已修复并推送至 `67fd630`，等待 CI 验证。
2. 本轮没有学校登录、网络抓课、Foundation 资源加载、Swift 类型检查、原生 UI/RTL/VoiceOver 或 CI 结果验收。报告不证明这些运行场景通过。
3. 上游截图工具未迁入的事实已单独记录。文档、工作树 gitlink 和历史构建产物不用于证明产品功能。
4. 完整覆盖矩阵以 `1e4fbec` 和表列三个 PR head 为依据；针对主会话新增 debug/theme 提交的相关消费链，增量复核截止于 `326cc8f50c1224a9cb44a51b1b25b334ba20d881`；缺口修复完成于 `67fd630`。后续提交若改变这些路径，需在新 SHA 上再次复核。
