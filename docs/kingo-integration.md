# Kingo v1.0.63 窄移植记录

## 范围与来源

- 目标工作树：`integration-parity-v1063`，基线 `6c9dec4`。
- 源工作树：`parity-v1063`，用户指定源提交 `774a4d6`。
- 仅集成 `JwWakeUpCompatParsers.swift` 的 Kingo super HTML 三链相关修复及
  `SleepyTests/JwKingoHTMLRegressionTests.swift`（源 16 项测试）。
- 独立验证入口：`scripts/tests/run_kingo_integration.py`。本次不修改工程文件或测试资源。
- 后续授权追加 `SleepyTests/JwNwpuPostParserRegressionTests.swift`（7 项完整 HTML 入口测试）；
  NWPU 生产类型修复由主 agent 完成，本任务只接入验证。工程注册仍由主 agent 处理。
- 目标的独立 `JwKingoZxParser`、`hasKingoTdGrid` confidence 让位及 ZX 委托、
  错误聚合、JZ/UMOOC/YL 及其他 parser 保持目标实现；源的窄 ZX 替代实现不移入。

## 证据与致谢

本次复用既有协议修复证据，不是重新做学校适配。已读：

- Android `app/src/test/java/com/lingion/sleepy/data/jw/JwKingoSuperSourceShapeTest.kt`：
  合法/非法节次、全角单双周、周次溢出、三链降级、七日水槽及 rowspan 行。
- Android `docs/history/wakeup-protocols-cross-verify-2026-09-15/protocol-matrix.md`、
  `findings/kingo-1.json`、`findings/kingo2-1.json` 和 `attribution-candidates.json`。
- 源 `docs/parity-v1063-audit.md`：历史 16 HTML + 19 WakeUp 独立测试记录，
  及整合独立 ZX 时保留委托与 confidence 的要求。历史通过不代替目标重跑。

沿用归档中的全部致谢（38 候选清单为真源）。其中 Kingo 相关证据包括
NYIST-CIPS/CourseTable、jiangyiqi99/CourseHelper、XingHeYuZhuan/shiguang_warehouse、
icepie/aischedule-lit-kingosoft，以及仅提供间接佐证的 wzj1122/jxufe-auto-evaluate；
本次未删改 License 或本地化中的既有致谢。

## 独立验证方法

- 真实本地 SwiftSoup package；复制目标生产 parser、Registry 及 frame capture 源码到新建专属临时包。
- 未复用/覆盖其他任务的 `kingo-v1063` 临时包；新包用 owner 文件校验当前工作树归属。
- 执行 `nice -n 15 swift test --build-system native -j 1 -Xswiftc -j1`，不使用模拟器或 xcodebuild。
- ZX 测试临时副本仅将 `Bundle(for:)` 改为 SwiftPM `Bundle.module`；资源字节及测试断言保持不变。

## 窄移植内容

生产改动全部位于 `parseKingoSuperHtml(_:errors:)`：

1. 严格周次正则支持全角/半角单双周括号；继续限制节次 1…30、周次 1…60，拒绝倒序、溢出及非法 token。
2. chain1 探测五/七日表头，从最右侧日列对齐，处理行首节次/时段列及其 rowspan。
3. chain1 动态定位 timing 行，合并其前教师行及后教室行，允许无教室及直接 td 内容；
   timing 位于第一行时跳过该块，后续合法块继续解析。
4. chain2 独立单双周列按逗号、中文逗号、分号、中文分号逐 token 应用；
   内联周次保留括号内单双周信息。三链优先级及错误聚合沿用目标实现。

## 验证结果（2026-11-03）

首次独立编译在目标基线 `JwNwpuPostParser.swift:190` 阻塞：`sectionChar` 是
`String?`，却用于 `[Character: Int]` 键，编译器报类型不符。该错误发生在测试执行前，
不能记作 Kingo 红测。

早期验证曾使用临时 NWPU 字典键适配。主 agent 随后将生产表达式修正为
`sectionChar?.first.flatMap { sectionBaseMap[$0] } ?? 0`；本脚本已移除
`--nwpu-key-compat` 开关和适配生成逻辑，并清除了专属临时包中的旧适配文件。
最终红绿验证均使用原样生产源码，未使用适配层或 mock。

迁入测试后的早期重试遇到主机调度阻塞和超时；切换 SwiftPM native build system 后完成验证。
native 在当前工具链有 deprecated 提示，保留此参数以满足本次串行独立编译约束。

| 测试组 | 修改 Kingo 前（RED） | 窄移植后（GREEN） |
| --- | --- | --- |
| 源 Kingo HTML | 16 项执行，7 项失败、28 个失败断言（其中 4 unexpected） | 16/16 |
| 既有 Kingo ZX | 9/9 | 9/9 |
| 既有 WakeUp | 19/19 | 19/19 |
| 新增 NWPU HTML | 7/7 | 7/7 |
| 合计 | 51 项执行，退出码 1 | 51/51，0 failures，退出码 0 |

NWPU 测试覆盖 nil/上/中/下/晚五种分支、无时段使用绝对节次、星期后周次不误作节次，
以及晚间偏移后不能超过第 13 节。类型表达式的最小 RED/GREEN 由主 agent 提供；
本任务新增的 HTML 测试首次运行即通过，不冒称它们经历过失败。

复现命令（红绿使用同一命令，先运行再修改 Kingo）：

```sh
python3 scripts/tests/run_kingo_integration.py \
  --swiftsoup /Users/kerrylee/Library/Developer/Xcode/DerivedData/Sleepy-bgzjsosfzbutwcasbwqemsmkxzrn/SourcePackages/checkouts/SwiftSoup \
  --package-dir /private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/kingo-integration-6c9dec4
```

日志根目录：`/private/var/folders/z3/7cz1vccj2g1clmqqqqh5x4y00000gn/T/opencode/`。

- `kingo-integration-red.log`：原始 NWPU 编译阻塞。
- `kingo-integration-red-tests.log`：早期超时，不算测试结果。
- `kingo-integration-red-native.log`：旧临时适配下的历史红测，最终结论不依赖此日志。
- **`kingo-integration-red-production.log`**：无适配生产源码红测，编译 20.11 秒。
- **`kingo-integration-green-production.log`**：无适配生产源码 51/51，编译 4.78 秒，测试约 0.54 秒。

## 自审

- 对照基线 `6c9dec4`，通过逐字检查确认 `JwWakeUpCompatParsers.swift` 在
  `parseKingoSuperHtml(_:errors:)` 之外完全相同，包括 JZ/UMOOC/YL、#32/#33、
  `JwKingoParser` 的 ZX 委托、confidence 让位、TaskActivity/父类回退与错误聚合。
- 完整 `JwKingoZxParser`、Registry、既有 ZX/WakeUp 测试及 ZX HTML 资源与基线逐字相同。
- 迁入 16 项 HTML 测试与源工作树逐字相同，SHA-256：
  `0b7270c19c81b3b9b6d63b4296f0fa91198a4a479c1cdf38cda9d020cd693609`。
- 独立包内全部生产 Swift 文件与最终工作树逐字相同；旧 NWPU 适配文件不存在。
- 审核了首行 timing 越界保护、严格节/周范围、三链先成功先返回、旧 ZX 稀疏周次与去重路径。
  本次窄移植未发现需要阻塞交付的新增问题。
- Python 语法检查和 scoped `git diff --check` 通过。本任务未 commit/push。

## 未验证

完整 iOS 工程编译、模拟器/UI、真实学校登录抓取、全量 parser 测试及发布均不在本次独立验证结果内。
本任务未修改 pbxproj；检查时新增 Kingo HTML 文件尚无显式 target 条目。
两个新增 XCTest 文件的工程注册交由主 agent，未以本次 SwiftPM 结果代替 Xcode target 验收。
