# v1.0.63：WakeUP 范围、系统动效与 undo/作息事务只读复核

日期：2026-11-04。串行完成；本轮只更新本专属文档和 `wakeup-share-integration.md`。未修改生产代码、测试、总矩阵；未编译、执行测试、启动模拟器、调用 swiftc、请求真实分享服务或提交推送。

## 证据边界

- Android：`/Users/kerrylee/sleepy` 的 `git diff v1.0.62..v1.0.63` 和 `git show v1.0.63:<path>`，不是当前工作区文件名猜测。两个 tag 分别为 `67c351e24754edd0d4a97a553005b4e272e7dca6`、`a821c6ace1e3e5dbfd02c7fbd738bf2ca1c8a223`。
- 下文 Android 路径以 `app/src/main/java/com/lingion/sleepy/` 为前缀；iOS 路径以本工作树 `Sleepy/` 为前缀。
- iOS：`/Users/kerrylee/sleepy-ios/.worktrees/integration-parity-v1063` 当前文件，包含主会话及其他切片 WIP。undo 已在 `a00c28e`，Repository 恢复失败保护和冻结删除已在 `9ddc96e`；读到了这两次实际提交的内容。行号为复核快照，后续共享编辑可能移动。
- 只提供静态调用链证据；以下“已有”不表示 CI 或视觉验收已通过。

## 1. WakeUP 范围裁定

新增 `data/jw/WakeUpShareClient.kt` 的 `fetchScheduleJson` / `fetchRawShareData` 只读取现成分享口令：`/pluto/app/antispam` → 解 signB 得 token → `/share_schedule/getv2` → 解出 shareData。`WakeUpShareProtocol.buildShareRequest` 的 RC4 明文是 `key=<口令>`。

实际 UI 消费是 `ui/screen/imports/ImportSheet.kt:1523–1557 buildImportPreview`：识别口令、await 获取、喂 `ScheduleParser.parse`。v1.0.63 全 Java/Kotlin 搜索未出现对应创建分享码调用；`ExportScreen.kt` 的 tag diff 只有 ICS 补 transfers，`ScheduleExporter.kt` 的 diff 是 fixedDate / ICS 调休日历展开。vendor `wake_up.js` 只有相同读取端点，是第三方兼容源而非官方 SDK。

**应删除总矩阵中“缺服务端分享码导出”的判断。** 建议 WakeUP 行描述为“服务端分享口令读取 + v6.1.70 加密链；Swift 实现及 fixtures 已写入，ImportSheet 接线/CI 验收由主会话完成”。不新增上传协议、导出 sheet 或上传测试。

## 2. 系统动效逐符号对照

| Android tag 中的真实变化和消费点 | 当前 iOS 实际承接 | 判定 / 最小后续范围 |
| --- | --- | --- |
| `ui/component/SleepyMotion.kt` 新增 `SleepyPopupScaleStart=0.8`、`SleepyContentScaleStart=0.92`、`SleepyPressScale=0.98`、`sleepyPopupEnter/Exit`、`sleepyContentEnter/Exit`、`sleepyExpandSpecs`。空间和透明度分开取 motionScheme 规格。原 `SleepyThumbSpring` 未改。 | `ui/component/SleepyMotion.swift:17` 只有原 thumb spring；`SegmentedSwitcher.swift:53`、`PillNavigationBar.swift:150,376` 实际消费它。 | thumb 的既有能力成立，但不是新增动效覆盖。缺新家族的共享策略及消费者接线。 |
| `ui/nav/SleepyMaterialTransition.kt` 的 `sleepyForwardTransform`、`sleepyPopTransform`、`sleepyPredictivePopTransform` 均改为 composable 工厂，并在 `SleepyNavHost` 的 NavDisplay 三槽消费。旧 110/220/200ms tween 被删；pop 目标页从不动改为 content 缩放淡入。 | `ui/nav/SleepyMaterialTransition.swift:25–110` 仍保留旧时长、pop identity；`SleepyApp.swift:1135–1206 PresentOverlay` 仅给覆盖页挂 `forwardTransform`，底下 `content` 未挂目标页入场；交互返回是 `dragX` 跟手。 | 有真实转场，但仍是旧行为。修改常量文件本身不够，还需目标页与覆盖页两侧消费。iOS 手势可保留平台语义，不能把未消费的 predictive 常量当已对齐。 |
| `MainActivity.kt:MainTabs` 从直接 when 改为 `AnimatedContent`，content scale+fade，`SizeTransform(clip=false)`；`SleepyNavHost.kt:RightHalfContent` 从 200ms fade 改同族。 | `SleepyApp.swift:846–849 tabContent` 直接 `screen(for: currentTab)`；`tabletRightPane:680–700` 为 0.2s opacity。`nativeTabs:732` 为系统 TabView。 | 自绘 tab 内容缺新增过渡，平板右栏仍旧 fade。系统 TabView 是独立平台承接，不能推断自绘分支也具备同样动效。 |
| `ui/theme/NoRippleClickable.kt` 两个普通 clickable 变体新增 pressed→0.98、fastEffects；新增 combinedClickable 明确不缩放，避免长按拖起常驻 pressed。 | `ui/theme/NoRippleClickable.swift:27–37` 仅 plain Button 包装；`theme/Theme.swift:241–246 SleepyButtonStyle` 只有 pressed opacity=0.7；`SettingsCard` 整卡是 onTapGesture。 | 无涟漪、禁用门控已存在；0.98 按压反馈未实现。需要覆盖实际点击面，不能只改无人消费的映射扩展。拖拽起点应保留例外。 |
| `SettingsCards.kt:SettingsCard` 展开使用 fastSpatial + 分离 fade，箭头 defaultSpatial；同轮接入 `AddCourseScreen` irregularOptions、`ImportSheet` 文本展开、`EditTableScreen`/`PeriodTableEditScreen` 节次展开、`GeneralSettingsScreen` 语言、`LicenseScreen` 两种折叠。 | `SettingsCards.swift:33,71–94` 有 0.31/1.0 spring 和 move(top)+opacity；`ImportSheet.swift:170–217`、`EditTableScreen.swift:173–241`、`PeriodTableEditScreen.swift:124–168` 走默认 withAnimation；`GeneralSettingsScreen.swift:680–734` 独立 expandAnimation；`LicenseScreen.swift:367–414` 默认 withAnimation；`AddCourseScreen.swift:1275` 有箭头 rotationEffect，但未见该块独立动画驱动。 | 部分“会展开”成立，但规格与分离空间/透明度并未统一。最小范围是共享展开家族和这些具体调用点，不是全面重做页面。 |
| `SettingsCards.kt:DisplayModeOption` 文字 fastEffects 渐变 + check popup；`SleepyNavHost.kt:CombinedRailItem` 容器和图标 fastEffects 变色。 | `SettingsCards.swift:224–237` 直接选色和 if check；`NavigationRailBar.swift:98–118` 直接选色，没有状态色动画。 | 新增选中态动画缺口。 |
| `PillNavigationBar.kt` 贴底/经典 Dock 的 badge 改 popup；`ScheduleScreen.kt` undo/redo 胶囊改 popup；新 `IntRangeSlider.kt` ghost 使用 popup 并保留退场快照。 | `PillNavigationBar.swift:262` 及 FloatingBar badge 是直接 if；`ScheduleScreen.swift:624` 直接 if 挂 undo/redo；`NativeBaselineSlider.swift:40` 用 `ghost.isHidden`，不是退场动画。 | 存在徽标/撤销/基线功能不等于新增显隐动效。需这些真实挂载点的进入/离开处理。六滑杆基线几何是另一个已实现切片，不应重复记为缺功能。 |
| `TimeSlotEditor.kt:ManualTimeSlotEditor` 原本已支持长按排序，本轮把 settle/cancel 改 fastSpatial、非法归位改 defaultSpatial，新增行入场与面板 animateContentSize；`TimeSlotRowItem` 新增容器色和 elevation 0↔6 动画。 | `TimeSlotEditor.swift:247–361` 是普通 VStack + ForEach、编辑时间和删除；没有拖动/settle 状态、行过渡或高度动画。 | 本轮增量的行/容器动画未接。排序本身是此前已有上游能力，须标“前置旧缺口”，不能写成 v1.0.63 新增排序。 |
| `ui/theme/Theme.kt:ColorScheme.transitioning/animateColorSlot` 新增 48 色槽逐项 defaultEffects 插值，`SleepyThemeProvider` 真正调用；刻意不重挂整树。 | `theme/Theme.swift:304–331` 算出 scheme 后直接 environment 注入；主题回调未提供该颜色插值策略。 | 全局主题渐变增量缺失；保留树身份的局部策略即可，不能靠整树 Crossfade 冒充。 |
| `CourseTableView.kt` / 新 `FloatOccurrence.kt:animateReturnToOrigin` 为浮课位置回弹、透明度、快速加课/操作条 popup 接线；实际标签中有 `if(false)` 的 popup，须按实际分支，不能算执行。 | `NativeCourseDrag.swift:298–328` 有真实 `UIDragInteraction` lifting preview、cancelling preview retarget，是 UIKit lift/取消承接；`QuickAddCourse.swift:103` 直接 if 显示选择层，没有 popup。 | 原生 lift/取消可作为平台语义证据，具体回弹仍待运行；不能声称复制了 Android 全部浮课动效。QuickAdd 显隐是仍需补的明确点；其他拖课状态由该切片验收。 |
| 新 `liquidglass/LiquidGlassNavigationBar` 由 `PillNavigationBar(dock=true,effectiveTheme=liquid_glass)` 实际调用，`SleepyNavHost` 提供 backdrop；内部 `SpringState`、`FlClashDockPhysics` 驱动 press/lift/travel/jelly、drag/fling，`LiquidGlassShader` 在 API33+ 跑 RuntimeShader，`LiquidGlassHaptics` 跨槽触觉。 | `util/NavStyleResolver.swift:69–77,144–146`：悬浮 + iOS26 → native，`SleepyApp.nativeTabs` 确实构造 TabView；低版本 → `PillNavigationBar.FloatingBar` 的 material + 普通 spring，没有 FLClash lens/drag 物理。 | iOS26 原生玻璃导航已有真实平台承接，不应记成全缺；低版本仅经典兜底。Android shader/物理实现细节不是必须机械搬运的 iOS API。平台差异和视觉验收分开记录，不能称全版本同构。 |
| `SegmentedSwitcher.kt` 本轮新增 SegmentOption badge 与 dbgTag 包装，thumb 动画仍用原 SleepyThumbSpring。`SleepyNavigator.kt` 新增的是路由方法。 | iOS thumb 原 spring 有调用；导航 methods 是业务路由。 | 不把这两个文件的改动整体算成“新增系统动效”。 |

**给总矩阵的建议**：将“系统动效待核对”改为“已逐符号核对：自绘页面/content/popup/按压/展开/状态色/主题插值存在明确增量缺口；iOS26 TabView、UIKit 拖放已有平台承接，运行未验”。不能统一标成全缺或全齐。

## 3. 实现 findings 与最小修复

### P2：在线课程的数值可以通过新转换层进入 parser 的溢出算式

- 位置：`data/share/WakeUpShareProtocol.swift:228–231,276–282`；消费者 `data/parser/ScheduleParser.swift:318`。
- `int` 接受 Swift 64 位 Int；`buildScheduleJson` 只检查字段能否转整数，没有检查节次跨度。合法五段结构中给某条 detail `startNode="9223372036854775807"`、`step=2`、其余字段使用现有 fixture，即可被转换为课程。下一步 `ScheduleParser.lossless` 执行 `startNode + step - 1`，Swift 有符号加法溢出会 trap，不能由导入的 Result/catch 转成错误。
- 同一类边界里，`normalizeNodes` 只限制数字形式大于 10000，数组分支 `nodes:[...]` 未受相同边界限制。4 MiB HTTP 上限不限制整数值大小。
- 这是新在线入口与既有 parser 的组合缺陷，不是密码学算法不匹配。Kotlin 的 `intOrNull` 为 32 位，也不能作为 Swift 放行整个 Int 域的依据。
- 最小修复：在在线转换层、返回 JSON 前验证节次/跨度及数组 nodes；用 checked arithmetic 验证末节可表示，并让数组/标量采用一致的节次上限，失败抛 `incompleteSchedule`。不需要改 parser 或加上传功能。
- CI 最小用例：用现有 fixture 替换上述两个值，期望客户端在交付预览前抛错；另补数组 nodes 越界。不要直接让 XCTest 同进程调用会 trap 的未修复 parser。现有 `testOversizedInputResponseAndNodeExpansionFailExplicitly` 只测标量 nodes 和 body 长度，未覆盖此链。

### P2（存量残留，非本轮恢复补丁新引入）：普通失败写入仍会清 redo、占用 undo 深度

- 位置：`data/repository/ScheduleRepository.swift:39–45,130–132,528–530`；`data/undo/UndoManager.swift:84–95`。
- 恢复失败保护已经修好，但普通 `insertTable` / `insertCourse` 等仍先调用 `captureForUndo` 再写库。例：创建 A/B/C → undo C（redo 中保有 C）→ 对 time_tables 注入 BEFORE INSERT 的 ABORT trigger → 尝试 insertTable D。D 的事务失败且库未变，但 capture 已清掉 redo，并向有限 undo 栈压入重复状态/可能挤掉最老一步。
- `9ddc96e` 的 diff 证实此前就存在 pre-write capture；本轮多步栈没有造成这一先后顺序，不应误报成新增回归。不过它限制了“失败保护已覆盖整个 undo 系统”的结论。
- 必要最小后续修复：对确认失败会被用户重试的普通写入口，像冻结删除一样在同一写事务取 before snapshot，成功 commit 后才发布 capture。仅 poll 回填不够，因为旧 redo/裁剪掉的历史已丢失。
- CI 最小用例：沿用 `UndoRepositoryHistoryTests` 的注入方法，在普通新写失败后验证 DB、旧 undo 次序、完整 redo 链均不变。现有六项 Repository 新测试测的是 undo/redo 的读失败和 apply 失败，不含普通 mutation 失败。

## 4. 没有发现新缺陷的已核实路径

### undo 与 period deletion

- `UndoManager` 双栈尾部出入；默认5/0清空禁用/任意负数不限；深度变更裁剪两栈；嵌套 batch 仅最外层首拍；恢复状态抑制 capture；失败回填不清对栈。这些都有对应断言，不是仅检查方法名存在。
- Repository undo/redo 当前先读取对称快照再 poll；apply 包含 courses→tables→periods 删除及反序插回的单 GRDB write；失败回填原栈；成功才写对栈并通知。读失败不触栈，apply 失败依赖 write 回滚。
- `deletePeriodTable:480–503` 在单次 write 内获取 owner、hydrate 当前共享节次、清 periodTableId/preBindSnapshotJson、删 period；commit 回调才捕获历史。`hydratedWith:71–77` 实际覆盖 nodesPerDay/timeJson/smartConfigJson，冻结的是当前有效值，不是绑定前旧快照。
- `ScheduleViewModel.deletePeriodTable:695–696` 显式删除传 `onlyIfUnbound:false`；草稿丢弃 `:701` 使用默认 true。`PeriodTableEditScreen:433–451` 当前确认文案是冻结语义并实际走该 VM 调用。
- `UndoHistoryDepthTests` 10 项、`UndoDepthPreferencesTests` 3 项、`UndoRepositoryHistoryTests` 6 项：深度/持久化/多步/批次/失败链覆盖具体结果。
- `PeriodTableFreezeDeletionTests` 3 项：两 owner 冻结+undo/redo、已收养草稿守卫、BEFORE DELETE ABORT 回滚。此文件未覆盖“已有 redo 时删除失败”及 unbound 成功删除；这是 CI 可补强范围，不能据此捏造当前实现错误。

### WakeUP 密码学、签名与网络生命周期

- 逐项对照 Kotlin tag：IP/FP/E/P/PC1/PC2（含重复46）、S-box、LSB-first、整块也补8字节及末字节长度；nativeHex 读每组第2/4字符；RC4 KSA/PRGA；MD5 和 cuid/adid；signA 明文、signB 前10字节校验及12..<22 token；RC4 key 17/15/3/60 变形链，未发现错译。
- 请求签名使用未表单转义值、UTF-16 字典序排序、无分隔连接后 Base64；正文另做 UTF-8 百分号编码/空格+，保留读取正文开头&和 antispam结尾&；两个 POST/请求头/did可选分支与来源相符。
- `WakeUpShareClient.swift:24–49` 真 transport 为独立 ephemeral URLSession、15s、流式4MiB、defer取消 task；非2xx、过大响应、JSON/errNo 在具体返回路径检查。`WakeUpShareImportModel` 用 generation 和 Task.isCancelled 挡迟到结果。
- 7 项 crypto 测试使用 vendor 固定向量，9 项 client 测试覆盖请求与合成响应编排；合成密文没有被称为独立密码学金标。
- **验证盲区**：client fixtures 替换的是整个 transport，因而请求取消测试证明取消传到假 transport，不能证明 URLSession 慢响应下的实际取消/重定向/分块上限。需要主会话线上 CI 用 URLProtocol/受控服务验这些路径；未观察到足以单独报缺陷的网络实现错误。未执行金标测试，不能写“密码学已验证通过”。

## 5. 主会话收口建议

1. WakeUP 总矩阵删掉在线创建/导出要求，按读取范围验收。
2. 动效按上表标状态；系统 TabView、UIKit 拖放与自绘缺口各用实际调用证据，避免同名文件即全齐。
3. 新在线数值边界问题交 WakeUP 代码负责人修；普通写失败历史问题作为存量残留明确裁定是否本轮收口，避免误当成已覆盖。
4. 运行以上 XCTest 及受控 transport/原生动效验收由主会话线上 CI 完成。本报告未运行任何测试，也不修改其他切片代码。

## 6. 两项修复交接（2026-11-04，补丁冻结，运行待 CI）

本节记录评审后的明确修复授权与实际补丁；上文第 3、5 节保留评审时的发现及建议。

### 生产修改

- `Sleepy/data/share/WakeUpShareProtocol.swift`：`nodes` 标量和数组元素统一为 `1...10_000`，课程首节、持续节数、作息行 node 使用同一范围。末节以 `addingReportingOverflow` 检查，且末节不得超过 10_000。非法整数（包括布尔、小数、不可表示的字符串）抛 `incompleteSchedule`。星期 `1...7`、类型 `0...3`、周次/最大周次为正的 32 位协议整数，并检查结束周不早于开始周。缺省 nodes/空数组仍可交由课程跨度补齐；无课程名对应的孤儿 detail 沿用过滤行为。
- `Sleepy/data/repository/ScheduleRepository.swift`：25 处普通写前 capture 全部迁移到 `writeWithUndo`。在一个 GRDB write 内取三表完整旧快照并完成业务写入，事务提交回调才 capture；通过连接的 `total_changes()` 排除没有执行写入的 guard/no-op。失败不发布快照，不清 redo、不占批次首拍。
- 插表与默认表切换、改表与课程重映射、diff 删除/更新/插入及边缘节次回收现在分别属于同一个事务，后半段失败会回滚前半段。事务内读写使用传入的 `Database`、entity 方法和已有 `InDb` 接口；认亲名册在删除前于同事务读取。补色和变更通知仍在事务成功返回后执行。
- 静态逐函数比较确认 `applySnapshot`、`restoreLastSnapshot`、`redoLastUndo`、`deletePeriodTable`、`saveOccurrence`、`moveCourseOccurrence` 函数体未改动。单独 `setDefault` 原本不捕获历史，本次保留其行为。

### 新增回归及冻结证据

先写以下两份新文件，再修改生产实现；已有测试、fixture 和断言均未编辑。新测试在生产修改前后哈希一致：

| 文件 | 新增 XCTest | SHA-256 |
| --- | ---: | --- |
| `SleepyTests/RepositoryMutationFailureTests.swift` | 29 | `c1cc57c047e6f8215f8e9f95a065bc7890696409e8ea2505296d03082ef12665` |
| `SleepyTests/WakeUpShareBoundaryTests.swift` | 5 | `86cbca5b85a57a7101457dfe66ab797b3cf65e850bb66005bb09c43d9dff9c5e` |

- Repository：初始化五步历史后 undo 两步，注入 INSERT/UPDATE/DELETE ABORT trigger。失败后比较三表编码值及通知次数，再走完剩余三步 undo 和完整五步 redo，检查每一步课表集合和栈耗尽结果。覆盖插表后默认切换失败、双表写入、作息复制、重映射、组替换、批量中途失败、diff 与删除后的回收失败。另验仅失败的嵌套批次，以及失败后成功的嵌套批次只占一个 undo 单元。
- WakeUP：构造五段原始数据，经 `parseRawScheduleData` → `buildScheduleJson` → 真实 `ScheduleParser.parse` 验证 1 和 10_000 边界、数字/字符串与数组形式。非法极值只调用转换层并断言错误，避免旧 parser 的溢出 trap 杀死 XCTest 进程。

### 验证与主会话动作

- 本机仅做源码审查、函数体对比、哈希及 diff 空白检查；没有运行测试、编译器、模拟器或真实分享服务。**尚无红灯/绿灯或编译通过证据。**
- 两份新文件由 `project.yml` 的 `SleepyTests` 目录规则收集；当前线上流程在构建前执行 `xcodegen generate --spec project.yml`，且单测关闭并行，适用于这些使用共享 UndoManager 的用例。此切片未修改工程、CI、UI、theme 或总矩阵，未 commit/push。
- 主会话线上先确认新增 34 项被发现；需证明红灯时，仅在隔离 CI 检出点使用旧两个生产文件配合新测试，随后验证完整补丁。不要将溢出输入直接送给旧 parser。
- 完整补丁同时回归 `UndoRepositoryHistoryTests`、深度/偏好测试、occurrence 单次操作与 `PeriodTableFreezeDeletionTests`，以及现有 WakeUP crypto/client 测试和课表编辑/作息绑定相关测试。运行结果由主会话记录。
