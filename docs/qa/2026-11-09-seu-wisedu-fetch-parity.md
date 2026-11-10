# SEU / Wisedu 抓取接线对齐

日期：2026-11-09。范围仅为恢复 Android 已有行为，不新增学校、协议、第三方来源或目录状态声明。

基线为 Android 精确标签 `v1.0.63`，解引用提交 `b16aa84d11c250acdf644cd8b7812ab27d03dc6a`。全部基线证据通过 `git show v1.0.63:<path>` 读取，未使用 Android 工作区当前文件：

- `app/src/main/java/com/lingion/sleepy/ui/screen/imports/JwWebViewLoginScreen.kt:489–509`：SEU 复用 Wisedu 抓取，允许 `ehall.seu.edu.cn` 门户根路径，并优先从主文档、其次同源 iframe 的 `#dqxnxq2` 读取所选学期。
- 同文件 `:968–979`：课表接口必须为成功 HTTP 响应、可解析 JSON 且包含 `datas.xskcb.rows` 数组；403、登录 HTML、错误对象进入错误回调。
- `app/src/test/java/com/lingion/sleepy/ui/screen/imports/JwWiseduWebViewContractTest.kt:37–44`：原有 SEU 门户和错误响应契约。

补齐 iOS `JwWebViewLoginScreen.capture()` 的 SEU 分支，并由独立 `JwSeuFetchJs` 对共享脚本执行相同的两处变体替换；同时恢复共享 Wisedu 课表响应校验。既有 `JwSeuParser` 的包装解码和 SKZC 位图能力不变。

## 来源、致谢与 fixture

沿用既有 `Sleepy/ui/screen/mine/LicenseScreen.swift` 的「东南大学 SEU」致谢记录。原有 Android `JwSeuParserTest.kt:9–14` 说明用户粘入数组形态来源为 `sakimidare/SEUTimetable`（Apache-2.0）的 `TableParserUtils` 输入契约；本次网关抓取行为直接取自 Sleepy Android 精确标签，无新引用或许可证变化。

原有 iOS `SleepyTests/resources/seu_courses.json` 与 Android `app/src/test/resources/jw/fixtures/seu/courses.sample.json` 字节相同，SHA256 均为 `b7940634ca9e41de49346428ffeed9c9d93d2bef3d97c0b45736cdf87f337d1e`。新增测试将其包装为网关 `datas.xskcb.rows`，仍断言解析出原有六条周次记录。

新增 `SleepyTests/resources/seu_gateway_android_v1063.js` 为从精确标签提取的 `WISEDU_FETCH_JS`，应用标签中 SEU 派发的两处替换。保留 Android 桥拼写，测试运行时仅提供 native 传输适配；不重写其协议逻辑。

`JwSeuFetchTests` 在 WKWebView 中通过本地 `WKURLSchemeHandler` 提供相同主文档与同源 iframe、模拟接口响应，分别执行该 Android 参考脚本与 iOS 生产脚本，比较完整请求序列和回调信封，而非仅检查源码包含字符串。覆盖主文档学期优先、iframe 学期、门户根路径域限制，以及共享 Wisedu 的有效 rows、403、登录 HTML、错误对象。

新增测试及参考 fixture 在生产修改前已写入并冻结；中央 build-7 发现学校类型为可选值后，经 root 授权追加 nil 学校类型不选取 SEU 脚本的断言并重新冻结，原有测试未改。测试源码 SHA256：`8c111b17e438af88408a964c14274f1824716f68454ad1c2920e7fa8f31b9842`；参考脚本 SHA256：`52bed16dff5781c146949ba12ece78aa2ca34fb4cce6cbc462a83472a0026640`。

## 验证边界

实施代理仅完成静态差异检查与原有 fixture 字节核对；构建、模拟器及测试运行由中央代理统一执行，结果应以中央日志为准。没有 SEU 真实账号登录验证，本地合成接口与 DOM fixture 不等同于真实账号验收；不据此提升学校目录的支持/验证状态。
