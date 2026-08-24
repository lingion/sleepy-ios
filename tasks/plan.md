# Plan · sleepy → iOS 逐行移植(按 planning-and-task-breakdown 校准重排)

**总原则**: 移植单位=文件,验收粒度=符号级。D0~D8 为 checkpoint 层,内部全部拆为 S/M 任务(≤5 文件),每任务独立可验证。

## 架构决策(spec 锁定,不重开)

- SwiftUI/iOS16.0(Xcode 14.3.1)· GRDB↔Room · WidgetKit 5 类 · 免费账号无签名 IPA→AltStore 重签
- **五道闸**(每批 exit 条件,缺一不算完)。G1~G3 静态逮"漏译",G4~G5 动态逮"接错":
  - **G1 符号覆盖**(静态): `scripts/coverage_audit.py` — Kotlin 符号 vs Swift 对应,diff 未映射项 → 零未解释项
  - **G2 用例对齐**(静态): Android @Test ↔ XCTest func test*,数量+名映射零缺漏
  - **G3 字符串 parity**(静态): 389 键×5 语言键集相等+非空
  - **G4 链条测试**(动态,新增): 函数间功能链完整性——解析器输出→DAO 落库→Repository→ViewModel→屏幕渲染,全链 XCTest 起真 app 内存栈走通,非喂桩。三张主链: ①导入链(六格式文本→parser→preview→confirm→DB→UI 显示) ②课程链(建表→加课→周次计算→三视图/今日列表数据一致) ③导出链(app 数据→exporter→文件→re-import→roundtrip 相等)
  - **G5 UI 冒烟**(动态,新增): XCUITest 起模拟器点真 UI——冒烟清单(建表→加课→三视图切换→WakeUp 文本导入→导出→切主题→切语言)自动化,替代 D6 手动冒烟;widget 走 gallery 快照验证(见 T7)
- **测试金字塔最终形态**(mobile-testing 选型): 单元=G1/G2 纯函数 · 链条=G4 XCTest 内存栈 · UI=G5 XCUITest · 真机=agent 驱动(见下)
- **全部测试线路 agent 接管**(含原"人工"线):
  - WKWebView 教务登录: 本地起 fixture HTTP 服务,逐协议放真实登录页+课表页 HTML 快照(wisedu/qz/zf/urp 各存 fixture),XCUITest 走完整 链:登录表单→提交→cookie→抓课表→预览→导入;**真站最后冒烟一次,唯一保留的人工动作=输账号密码或贴 cookie**(教务账号我变不出来,不装能)
  - 真机线路: iPhone 插线后 `xcrun devicectl` 装 app+launch+`simctl io screenshot` 同款截屏断言+日志抓取,全部我驱动;AltStore 侧装机=你按一次安装键(手机上操作,物理够不着)
  - D8 验收: 原"人工逐项对照"→ ln-42 验收矩阵,每行=受保护结果/测试路径/oracle/命令/PASS 证据,你看矩阵签收,不逐项手点

## Skill 调度表(全菜单扫描后 22 个相关;每批打勾可查)

| 时机 | skill | 状态 |
|---|---|---|
| spec/plan(已过) | spec-driven-development · planning-and-task-breakdown | ✅ 已调 |
| D0 前 | context7(GRDB 6 API 核实)· source-driven-development(WidgetKit/GRDB 官方文档) | 开工时调 |
| D0 后计划复审 | ln-11-plan-reviewer | D0 末调 |
| 每任务实现 | incremental-implementation | 每任务 |
| 每测试移植 | test-driven-development · unit-testing | 随测试 |
| D1 后 | database-testing(schema/迁移 parity)· ln-25-persistence-auditor | D1 末 |
| D2~D6 | source-driven-development(ICS/CSV 规范核对)· frontend-ui-engineering(D5/D6) | 各批 |
| D3 后 | ln-23-test-suite-auditor(移植测试是否证明行为) | D3 末 |
| G4 链条测试 | mobile-testing(✅已调,选型结论入架构决策)· test-driven-development | D1/D3/D6 随链建 |
| G5 UI 测试 | mobile-testing(XCUITest 冒烟自动化)· exploratory-testing(D6 末模拟器探索一轮) | D6 末 |
| 测试环境分层 | test-environments(✅已调): 本机模拟器=CI 位,真机=release 位;fixture HTTP 服务对应真教务;无云端农场(自用项目,环境=两台真机+模拟器全在本机) | D0 定盘 |
| 风险矩阵 | risk-based-testing(✅已调): 教务导入/周次计算/数据库迁移=CRITICAL 区,widget/通知=HIGH,外观=LOW;测试密度按矩阵分,不撒胡椒面 | D0 定盘进 tasks/risk-matrix.md |
| 验收矩阵 | ln-42-acceptance-test-builder(✅已调): D8 验收=受保护结果×测试×oracle×证据 表格,非手点清单 | D6 起建,D8 完 |
| 测试数据 | test-data-management: Android 51 个 @Test 的 fixture 逐个迁 Swift 测试资源;教务 HTML 快照 fixture 新建 | D1~D3 随测 |
| 缺陷线路 | bug-reproduction(红→最小复现→failing test)→ ai-bug-triage 分类 | 随时 |
| 可靠性 | test-reliability(XCUITest/链条测试 flake 治理,重跑≠pass 掩盖) | 每次红 |
| 验收 gate | release-readiness(证据 go/no-go,喂 D8 矩阵) | D8 |
| T7.1 前风险决策 | doubt-driven-development(App Group 免费签名可行性对抗审查) | D7 前 |
| 每 checkpoint | review(diff 审查)· verification-before-completion(证据验收) | 每批末 |
| 出 bug | systematic-debugging(CLAUDE.md bug-report 定向) | 随时 |
| 全程 | git-workflow-and-versioning(sleepy-ios 独立仓原子提交) | 随时 |
| 平台差异决策落档 | documentation-and-ars(SPEC 差异表 10 条=ADR) | D0/D8 |
| D8 | shipping-and-launch(装机清单) | D8 |
| 🚫不调 | dispatching-parallel-agents · subagent-driven-development(用户未要求不开 Agent)· docx/pptx/web 系 ~100 无关项 | — |

---

## Phase D0 · 脚手架

- [ ] **T0.1 工程骨架** — project.yml(app+widget ext+**SleepyUITests target 三件套**)+目录树镜像 Android 包结构+五语言 Localizable.strings 空骨架+GPL 头。
  - 验收: `xcodegen generate` 成功;三 target `xcodebuild build` 过 · S
- [ ] **T0.2 构建链+G1闸** — build-ipa.sh(xcodebuild archive→无签名IPA);SPM 经 gh.qdp.qzz.io 拉 GRDB;coverage_audit.py 可跑。
  - 验收: 产出 .ipa;audit 脚本空工程输出 0 基准 · M
- [ ] **T0.3 风险矩阵+环境定盘** — risk-based-testing 六相输出 `tasks/risk-matrix.md`(教务导入链/周次计算/DB 迁移=CRITICAL,widget 数据同步/通知=HIGH,外观/关于=LOW,测试密度按区配);test-environments 定两环境: 模拟器(iPhone 14/iOS16.4,已知在线)=开发+CI 位,真机=release 位;教务 fixture HTTP 服务脚手架。
  - 验收: 矩阵每行有 impact×probability×区+对应测试层;`scripts/fixture_server.py` 起服务返回一张登录页+一张课表页 · M
- [ ] **CP-D0**: IPA✓三target编译✓GRDB链接✓矩阵落盘 + ln-11-plan-reviewer 复审本计划 → **用户过目再开 D1**

## Phase D1 · 数据+util 底座(6 任务)

- [ ] **T1.1** entity 3 文件(CourseEntity/TimeTableEntity/SmartPeriodConfig: GRDB struct,字段逐一)· S
- [ ] **T1.2** dao+库 3 文件(CourseDao/TimeTableDao/AppDatabase: SQL 语义逐条)· M
- [ ] **T1.3** DateUtils/TimeTableUtils/CourseColorUtil + DateUtilsTest/CourseColorUtilTest · M
- [ ] **T1.4** AppPrefs(键名不变)/LocaleHelper + AppPrefsIsolationTest · S
- [ ] **T1.5** VersionUtils/UpdateInfo/UpdateManager(安装动作=差异#2) + 2 测试 · S
- [ ] **T1.6** PinyinMatcher(311 行数据表全搬)+ 五语言 389 键全量搬运 + StringsKeyParityTest(G3 闸激活) · M
- [ ] **T1.5b G4-链①前半** — 课程链条测试: 建表(DAO)→加课→DateUtils 周次计算→按日/按周查询,内存 GRDB 栈起 app 数据层全链走通(不起 UI)· S
- [ ] **CP-D1**: 7 测试文件绿 + G1 符号零缺 + G4-链①绿 + database-testing + ln-25-persistence-auditor 过

## Phase D2 · 教务 jw(3 任务)

- [ ] **T2.1** 协议+小解析器 7 文件(JwCourse/Protocol/SchoolInfo/Parser/Qz/QzCrazy/Urp) · M
- [ ] **T2.2** 大解析器 3 文件(NewUrp 193/NewZf 324/Wisedu 113) · M
- [ ] **T2.3** JwImportViewModel(237)+ Jw 三测试全用例(G2) · S
- [ ] **CP-D2**: jw 测试绿 + G1/G2

## Phase D3 · 解析器+导出(2 任务)

- [ ] **T3.1** ScheduleParser 738 行六格式逐函数(WakeUp文本/JSON/ICS/CSV/HTML/纯文本)+ source-driven 核对 ICS/CSV 规范 · L→拆两个 session,单文件仍一任务(符号闸兜底)
- [ ] **T3.2** ScheduleExporter(187,三格式)+ ScheduleRepository + ExportImportRoundTripTest · M
- [ ] **T3.3 G4-链②/③** — 导入链(六格式文本→parser→DB→Repository 查询一致)+ 导出链(app 栈→exporter→re-import roundtrip),内存栈 · M
- [ ] **CP-D3**: 往返测试绿 + G4-链②③绿 + ln-23-test-suite-auditor

## Phase D4 · 主题(1 任务)

- [ ] **T4.1** Theme(390)+ThemePresets(371): 5 预设×Light/Dark+跟随系统+HSV,色值逐 hex · M

## Phase D5 · 通用组件(3 任务)

- [ ] **T5.1** 小组件 4(PillNavBar/SegmentedSwitcher/DateTimePickers/CourseDetailSheet) · M
- [ ] **T5.2** CourseTableView(716,三视图网格核心,单文件单任务) · L(符号闸兜底)
- [ ] **T5.3** SmartPeriodEditor(455)+TimeSlotEditor(241) · M
- [ ] **CP-D5**: Preview 全渲染+编译零警告

## Phase D6 · 屏幕(5 任务)

- [ ] **T6.1** ScheduleScreen(427)/ScheduleViewModel/TodayScreen(252) · M
- [ ] **T6.2** AddCourseScreen(1258,单文件单任务) · L(符号闸兜底)
- [ ] **T6.3** MineScreen/AllTablesScreen/EditTableScreen(369)/ManagementPage · M
- [ ] **T6.4** ExportScreen(347)/ReminderScreen(601)/AppearanceScreen(420)/GeneralSettings/AboutScreen(367)/UpdateChangelogDialog · M(5文件线,拆半也行)
- [ ] **T6.5** 导入流程: ImportSheet(911)/SchoolSelectScreen(522)/JwImportFlow(314)/JwWebViewLoginScreen(517,WKWebView)/onOpenURL(差异#4) · L 拆两 session
- [ ] **T6.5b 教务 fixture 链** — fixture 服务器铺 wisedu/qz/zf/urp 四协议登录页+课表页 HTML 快照,XCUITest 走全链(登录表单→cookie→抓课表→预览→导入→三视图显示一致);真站冒烟一次(仅输账号动作留你,其余我盯日志) · M
- [ ] **T6.6 G4-链①后半+G5** — ViewModel↔屏幕接线链条测试+ **XCUITest UI 冒烟自动化**(建表→加课→三视图切换→WakeUp导入→导出→主题→语言)+ exploratory-testing 探索一轮 · M
- [ ] **CP-D6**: XCUITest 冒烟+教务 fixture 链全绿 + G4 三链全绿

## Phase D7 · Widget+通知(4 任务)

- [ ] **T7.0** doubt-driven-development 对抗审查: App Group 免费签名可行性→定 T7.1 走向
- [ ] **T7.1** widget 数据层: WidgetContent/WidgetTableResolver/WidgetUpdater(差异#6)+共享方案实测 · M
- [ ] **T7.2** 小 widget 3(Today/TwoDay/WeekList,排版逐函数=差异#5) · M
- [ ] **T7.3** 大 widget 2(WeekView/WeekGrid 695)+gallery 预览(差异#7) · M
- [ ] **T7.4** CourseNotificationScheduler(539)→UNUserNotificationCenter(差异#1)+ReminderScreen 联测 · M
- [ ] **CP-D7**: 模拟器 gallery 5 widget 渲染+通知触发(XCUITest 断言,非肉眼看)

## Phase D8 · 壳+分发(2 任务)

- [ ] **T8.1** SleepyApp/MainActivity(282,导航+onOpenURL)+全 app 联调+G1 终审(76 文件全绿) · M
- [ ] **T8.2 真机验收(agent 驱动)** — IPA→AltStore 安装(你按装键)→**devicectl 装调试版先行全项自动化**(三视图/编辑/导入/导出/5 widget/通知/主题/多表,每项=启动→操作→截屏断言→日志核查);AltStore 正式版复测 App Group/重签路径;**验收矩阵**(ln-42: 受保护结果×测试×oracle×证据)交你签收 · L
- [ ] **CP-D8**: 验收矩阵全 PASS + release-readiness go/no-go → 你签收=完

## 风险表

| 风险 | 概率 | 预案 |
|---|---|---|
| App Group 免费签名不生效 | 中 | T7.0 对抗审查先行;文件直读兜底;仍败→ask 付费 |
| GRDB 镜像拉取失败 | 低 | raw SQLite3 薄 DAO(ask) |
| WKWebView 教务站兼容(验证码/UA) | 中 | T6.5 真机早测,不拖到 D8 |
| 跨会话上下文丢失 | 高 | FILE_MAPPING+todo 勾选=唯一事实源,任务完即更新+git commit |
| 翻译走样(概括重写) | 中 | G1 符号闸+每批 review+用户随机抽文件对照 |
| iOS16 SDK 组件缺口 | 低 | 等效 SwiftUI 实现,不降功能 |

## 对"保证"的正面回答

不能保证零缺陷——但保证:漏函数=G1红灯;测试缩水=G2对不上;字符串漏=G3红;**函数翻译对但接线丢=G4链条红**(三链跨 parser/DAO/Repo/VM/UI 数据一致);**UI 挂了=G5 XCUITest 红**;最终签收=你真机对照而非我自评。不可机械验证项(动效/像素排版/WKWebView兼容)全部有真机兜底点,不裸奔。

## 兜底流程(测试红了/验收挂了怎么办)

1. **红闸即停**: 任何闸红 → 当前批冻结,禁进下一批。systematic-debugging 定位(根因四类: ①漏译 ②译错 ③平台差异未适配 ④原 Android bug 被忠实带过来)
2. **④类特殊处理**: 原 app 就有的 bug → 🚫顺手修(违反忠实翻译),记 `known-parities.md` 清单,D8 验收时你决定要不要单独修
3. **修复回路**: 定位→最小修复→对应闸复跑绿→review 该 diff→git commit(附 Android 原文行号引用)
4. **D8 真机验收挂**: 逐项记缺陷清单 → 回到对应批次修 → 重新出 IPA → 复验,直到清单空
5. **模拟器过真机挂**(App Group/重签/触摸差异): risk 表已列,T7.0 对抗审查+文件直读预案,D8 前不盲进
6. **quality-postmortem**: 若验收阶段同一类问题逃逸 ≥2 次,跑 postmortem 把闸补上新类别(闸体系可增量,不是写死的)
