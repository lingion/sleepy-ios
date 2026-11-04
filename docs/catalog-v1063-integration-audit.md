# v1.0.63 教务目录集成审计与待补能力

审计日期：2026-11-03。目标基线 `6c9dec4`（integration-parity-v1063），来源 `774a4d6`（parity-v1063）。Android 证据固定到本地 `sleepy` 仓库的 `v1.0.62` / `v1.0.63` tag。

**结论：不能整份覆盖目录，也不能把目录收录或可尝试入口计为已支持学校。以下分组是后续集成待办，不是永久删除迁移范围。** 本轮目录调查仅用本地 Git、现有文档与 fixtures；没有网络批量搜索、登录学校或运行模拟器。`schools.json` 未改。

## 1. 目录来源和差分事实

使用 Python 读取 `git show <ref>:<path>`，按 `catalogId` 比较 JSON 对象，输出计数而非数万行 JSON。

| 项目 | 结果 |
|---|---|
| 两侧条数 | 各 4140，catalogId 集合完全相同，无新增/删除/换 ID |
| 源目录 | `774a4d6` = `f95ee1e` = Android v1.0.63（字节一致） |
| 目标目录 | `6c9dec4` = `0f0ebfa`（#31）= Android v1.0.62（字节一致） |
| 有字段变化 | 1405 条 |
| 字段范围 | 仅 status、type、url、enableFetch；名称、别名、排序等其余字段全同 |
| 有非空 URL | 目标 1478，源 2880；不能称为成功导入学校数 |

SHA-256：

- 目标 / Android v1.0.62：`a786c44e1e36543864ecf5d271c8f21ebdfc5297d0bdad26087cde945f75ee38`
- 源 / Android v1.0.63：`c671f07f6ccfe42aeb529ac76a940aac89b3986e56fdc11e8519055fcb6b33b0`

### 1.1 实际增量来自哪些提交

下列统计为各 Android 提交与其第一父提交的目录语义差分：

| 提交 | PR | 实际目录变化 |
|---|---|---|
| `8c9c34c3` | #232 | 宁波城市职业技术学院：协议改判、supported、fetch=true |
| `9d5439a7` | #243 | 南开：显式 supported、fetch=true |
| `ef60b35c` | #247 | 42 条 pending → unverified，填 type/url |
| `26c1adbb` | #251 | 55 条 pending → unverified，填 type/url |
| `2b896ffd` | #254 | 1305 条：1257 pending → unverified、48 grad_pending → grad_unverified，填 type/url |
| `e4f38f45` | #272 | 佳木斯：移除 unverified 和显式 enableFetch=false |

合计：42 + 55 + 1305 + 3 = 1405。

`f95ee1e` 标题的“43 校晋升”与正文“新增两校、删除两校、1404 处 pending 晋升”不能作为本次迁移账本。#31 已带入 4140 条目录；目标与源没有条目增删。Android #254 的 `findings.md` 和提交正文保留了“43 operational”的中间结果，但该 squash 的后续变更继续全量吸收，最终提交树改变 1305 条。历史文案不能替代最终资产对账。

## 2. 1402 条候选准入变化

精确字段：

```text
url:    空串 → 源目录中的精确 URL
type:   null → 源目录中的精确协议标签
status: pending → unverified              1354 条
        grad_pending → grad_unverified      48 条
enableFetch: false → false                全部 1402 条
```

Android `v1.0.63:docs/catalog/manifest.json` 的 ownershipAudit 对这 1402 条全部记录：

- `ownershipStatus=unknown`
- `authenticatedImportTested=false`
- action 分布：`retained-shiguang-declared-owner` 42、`retained-shiguang-adapters-owner` 55、`retained-wakeup-662-declared-owner` 1305。

Android `2b896ffd:scripts/catalog_ownership.py` 新增的 `wakeup_662_declared_owner` 接受官方目录声明，不要求活性探针成功；保留 HTTP(S)、无凭据/脱敏占位、公网 host 等安全条件。`docs/wakeup-catalog-absorb-2026-10-28/scope.md` 明确一律 unverified、enableFetch=false、用户自选导入。它是有来源的准入策略变化，不是逐校实测支持证据。

### 2.1 iOS 当前能力分组与恢复条件

以目标 `6c9dec4` 的 `JwParserRegistry.factoryFor` 实际工厂集合判定，不仅检查协议常量是否存在：

| 分组 | 本科 | 研究生 | 合计 | 后续集成条件 |
|---|---:|---:|---:|---|
| 已有 Registry 工厂 | 523 | 26 | **549** | 可迁移精确 url/type；状态只允许未验证候选准入，须保留确认弹窗、草稿恢复门控和 false 标记。注册存在不证明逐校可用。 |
| `jw_home` | 788 | 22 | **810** | 需要登记型解析器、Registry 注册与按空白协议处理的自动检测通路；补齐之前不把“有 URL”包装成可导入。 |
| `sg_asset` | 43 | 0 | **43** | 需要拾光脚本解析器、WebView bridge、脚本/manifest 资产与许可，以及按具体学校名命中的验证。 |

810/43 均应继续作为待集成范围保留，不能因当前 iOS 缺实现就永久舍弃。当前若只同步元数据，可保留 pending/grad_pending，待通路与验证齐备再开放 unverified；注意 `loadSchools()` 仅按非空 URL 过滤，填 URL 本身就会改变列表展示。

1402 条 type 分布：jw_home 810、zf_new 221、qz 131、kingo_new 49、sg_asset 43、classic_eams 24、shuwei_json 15、zf 14、urp_new 12、chaoxing 11、cf 11、xju_post 7、south_soft 7、umooc 6、suda_post 5、urp 5、qz_with_node 5、wisedu 5、cf_new 4、scau 4、cumtb 3、qz_crazy 3、yl 2、hniu/ecupl/eams5/qz_br/nwpu_post 各 1。

### 2.2 是否推翻更谨慎的上游状态

相对 Android v1.0.62：521 条原为 `withheld-new-unproven-owner`，1 条原为 `withheld-domain-collision`，880 条无对应 ownership decision。因此批量开放确实改变旧版更谨慎策略，但有后续 Android 明确策略变更依据，不能说成 iOS 凭 URL 自行推断支持。

唯一旧域冲突条目：吉利学院 `moe:4111012802`。

```text
url=https://jw.guc.edu.cn/yethan/UserAction?setAction=userLogin
type=qz
```

`ef60b35c` / v1.0.63 的 `scripts/data/school_url_evidence.json` 记载页面标题“用户登录-吉利学院教务管理信息系统”，但仍 unknown/low、未登录导入。该证据解释重新准入来源，不能证明协议成功或晋升 supported。

Android v1.0.63 最终保留的 1260 条 pending/grad_pending 与目标完全相同。本差分没有覆盖上游最终仍被拦停的条目。旧 `docs/catalog/README.md` 的 1478 条计数及更严格准入叙述属于历史文档，须结合最终 manifest、策略代码和提交链理解。

## 3. 三校独立裁决

### 3.1 南开大学 `N_南开大学`

```text
status: 缺失 → supported
enableFetch: 缺失 → true
type/url 不变：classic_eams / https://eamis.nankai.edu.cn/
```

- 目标 `normalizeStatus(nil)` 已是 supported，缺失不是 legacy 状态。显式 status 可迁移，运行时属于等价规范化。
- fetch=true 不能独立代表能力补齐。Android #243 配套 classic EAMS 形态 B、入口页自动导航/抓取和帧采集处理。
- 证据：Android `docs/history/nankai-cross-verify-2026-10-27/reporter-dump-analysis.md:23–35`。旧根入口 WRONG_PAGE；测试包修复后用户回传“可以正常导入”，空白页面不妨碍原生 XRW 请求。
- fixtures：Android `app/src/test/resources/jw/fixtures/classic_eams/nankai-{course-table-action,entry-page,iam-login-page}.html`；契约测试 `NankaiClassicEamsWebViewContractTest.kt`。
- iOS 基线 `JwWebViewLoginScreen.swift:363–473` 无 classic EAMS 专用分支，未发现南开对应 fixture/契约测试。

待办：保留现状兼容；fetch 开闸与入口/抓取实现、fixture 验证一起迁移，不把布尔开关当实现。

### 3.2 宁波城市职业技术学院 `moe:4133012645`

```text
type: shuwei_json → classic_eams
status: unverified → supported
enableFetch: false → true
url 不变：https://webvpn.nbcc.edu.cn/login
```

- type 改判有明确直接证据，应作为元数据纠错迁移；旧树维标签来自目录猜配。
- 证据：Android `docs/nbcc-cross-verify-2026-10-26/pc-entry-evidence.md:32–37,59–64`；用户 Android 测试包回传导入 146 门课成功。
- 成功链为桌面 UA → PC 教务 → classic EAMS 形态 B 同源抓取。目标基线仍默认移动 UA，缺相应抓取链。
- fixtures：Android classic_eams 目录内 `nbcc-course-table-action.html`、entry/login/empty-shell/mobile-spa-shell、shuwei-mixed.json；契约测试 `NbccClassicEamsWebViewContractTest.kt`、`ClassicEamsWebVpnTest.kt`。

待办：type 可独立纠正；暂保留 unverified/false。补齐 UA 与 WebVPN 形态 B，再验证后决定 supported/fetch。Android 146 课结果不是 iOS 成功证明。

### 3.3 佳木斯大学 `moe:4123010222`

```text
status: unverified → 删除字段
enableFetch: false → 删除字段
type/url 不变：kingo_new / https://jwxt.jmsu.edu.cn:456/jmsujw/cas/login.action
```

- 删除 status 会归一为 supported，不能当成无害字段清理；删除 enableFetch 仍默认 false，没有运行时收益。
- Android #272 转正与 Kingo 修复绑定：导轨/rowspan 星期对齐、周末课程、动态时间行、全角单双周括号。测试 `JwKingoSuperSourceShapeTest.kt` 包含带导轨 7 天课表与无教室课程。
- iOS 基线 `JwWakeUpCompatParsers.swift:1213,1237–1264` 仍为旧规则，含 `day=column+1`，缺 distanceToLast/timingIdx/totalDays。
- 来源 `774a4d6` 已有上述修复，`SleepyTests/JwKingoHTMLRegressionTests.swift:40–83` 等提供回归用例。其他 agent 可能正在集成，应核对最新 diff/验证结果后更新本项，不能因本审计基线缺失而重复覆盖。

待办：保留 unverified/false，先集成并验证 Kingo 修复，再独立审查状态转正证据。

### 3.4 证据账本不完全一致

Android v1.0.63 manifest 对南开/NBCC/佳木斯的 authenticatedImportTested 仍均为 false，NBCC/佳木斯 ownershipStatus 仍 unknown；南开和 NBCC 的人工回传证据在专项文档。应保留这种元数据与专项记录的差异，不擅自将 manifest 改写成“已全部验证”。本轮没有学校登录或 iOS 真实导入验证。

## 4. 真实状态门控与本次独立修复

基线问题：`JwSchoolInfo` 缺 `isUnverified`，但 canImport、选校确认、草稿恢复和报告均引用它；isGrad 漏 grad_unverified。本切片仅修复这两个属性，并纠正 normalizeStatus 注释（缺省兼容 supported，未知 fail-closed 到 pending）。

规则仍为：

```text
isUnverified = unverified 或 grad_unverified
isGrad = grad_supported / grad_pending / grad_unverified
canImport = (isSupported 或 (isUnverified 且 Registry.supports(type))) 且 hasUrl
草稿需确认 = phase == webViewLogin 且 (!canImport 或 isUnverified)
```

- supported/grad_supported 保留既有兼容语义：type 非空即可进入 supported 分支，不额外新增 Registry 检查。本次“未知 type 拒绝”测试针对未验证准入；不声称历史 supported 分支已加固。
- pending/grad_pending/legacy 即使有已注册 type 与有效 URL 也不能导入。
- configureConfirm 阶段不重复要求选校确认；未验证的 webViewLogin 草稿往返 codec 后仍须确认。
- nil/空 status 保留 supported；未知 status 归一 pending。
- URL 要求 HTTP(S)、非空 host、无用户名或密码；不是学校归属、活性或登录成功验证。
- enableFetch=false 不是全局禁 fetch 保证：当前 WebView 多个分支直接按 type 派发；`JwFetchProtocol` 仅在部分强智策略读取该字段。

## 5. 回归验证与边界

新增 `SleepyTests/JwSchoolStatusRegressionTests.swift`（7 个测试），覆盖七状态完整矩阵、未验证未知协议拒绝、有效/无效 URL、旧 nil normalize、真实草稿 codec 往返和确认阶段、53 项真实 Registry 支持面。

运行：

```sh
nice -n 19 python3 scripts/jw-school-status-check/run.py
```

独立 harness 在临时目录生成无依赖 SwiftPM 包，单 job、编译线程 j1、低优先级，使用 native build system 避免 App/Xcode 构建。当前工具链提示 native 已弃用，后续工具链升级需复核此选项；本次实际可用。

编译执行的生产文件保持原样：JwSchoolInfo.swift、JwImportDraft.swift、JwCourse.swift、**完整 JwParserRegistry.swift**。不是手写 supports 白名单 stub。协议常量从实际 JwProtocol 提取，工厂集合与独立固定的 53 项审计集合精确核对。解析器实体及诊断载体为隔离占位；任何解析器构造/执行均 fatalError，防止误把该 harness 当解析器测试。

证据：

1. RED：原模型因 `JwImportDraft.swift:43` 引用不存在的 isUnverified 编译失败。
2. 仅补 isUnverified 后，再次 RED：7 测试、1 失败；grad_unverified 实际 `[false,true,false,false,true]`，预期 `[false,true,true,false,true]`。
3. 补齐 isGrad 后 GREEN：2026-11-03 21:51，**7 测试、0 失败**；53 项 Registry 工厂集合核对通过。

新增测试从正式 RED 到 GREEN 未修改；旧测试未修改。本结果不覆盖解析器正确性、WebView/UA/脚本桥、真实学校导入或整个 App 的编译。没有 xcodebuild、模拟器、commit/push。

## 6. 后续集成顺序

1. 合入本状态切片及测试，保留 #31 的 catalogId、状态和 Registry 能力，勿整文件回退到来源分支旧模型。
2. 集成、验证 Kingo 修复；单独决定佳木斯状态。
3. 纠正 NBCC type，补 classic EAMS 入口/UA/WebVPN/抓取与南开/NBCC fixtures，独立验证后再开闸。
4. 将 549 条按未验证候选口径迁移，保持确认链和 enableFetch=false；不按 URL 宣称支持。
5. 补齐 810 条 jw_home 自动识别与 43 条 sg_asset 脚本通路，再恢复对应候选准入；保留完整待办范围和来源。
6. 最后以 catalogId 重新复算字段差分、状态/URL 计数、Registry 可路由集合及来源证据，禁止用过期 PR 标题替代验收。
