# v1.0.63 教务协议/目录迁移

## 范围、证据与致谢

固定来源为本地 Android `v1.0.62` / `v1.0.63` tag；复用已有跨仓调查，不重新搜索、
不启动子代理。遵守本轮限制：不运行本机编译、测试、模拟器、swiftc 或测试脚本，
不提交推送。验证结论只允许引用此前 Kingo 51 项历史结果，新改动待线上 CI。

- 目录差分依据：`docs/catalog-v1063-integration-audit.md` 的 4140 身份、1405 差异账本。
- 拾光实现依据：Android `JwSgAssetParser.kt`、`JwSgAssetBridge.kt` 及
  `assets/third_party/shiguang/manifest.json`。
- 拾光来源：**ShiGuangSchedule/shiguang_warehouse / 星河欲转 / MIT**，
  manifest 固定 commit `7c9e1907635cb1c2d481b316e6f52d69dc77edff`。
  所有脚本、manifest、MIT 原文按 Android tag 原字节导入，保留各脚本作者标注与
  adapter maintainer。MIT 原文位于 `Sleepy/resources/third_party/shiguang/LICENSE-MIT.txt`。
- 南开/NBCC：Android `ClassicEamsWebVpn.kt`、`CLASSIC_EAMS_FETCH_JS` 以及对应 fixtures。
  继承其全部归档致谢，不因本次仅迁移抓取链而删除既有候选。
  直接形态证据含 Wangxiaolu0716/class-schedule、jxy18100/nku-、zawnpn Dart 链、
  liyue983 用户脚本；源文档中的 Android 人工成功结果不等同于 iOS 成功。
- 佳木斯：复用已集成 Kingo 三链/七天/rowspan 修复及 51 项历史 harness 记录。

## 迁移策略

1. `jw_home` 为零置信登记器，不进入 TYPE_PRIORITY；parse dispatch 按空协议自动识别。
2. `sg_asset` 使用精确 NFKC 校名查询 manifest 首个 adapter，bundle 内加载原 JS。
   shim 只传输 courses JSON、periods、startDate；原生 parser 保守跳过自定义时间。
   对话框策略与 Android 相同：alert 继续、prompt 原 defaultText、selection 默认项。
   组合课表显式失败；无提交完成显式失败；120 秒最终消息超时；重复点击取消前次回调。
   43个当前学校脚本均有 notifyTaskCompletion；课程先缓存，完成后才合并发送，
   防止 AUFE 等先保存课程、后保存作息/学期的调用顺序丢失元数据。
3. 拾光周次只在完整等差步长 2 时压缩单双周，避免上游 `[1,5]` 压成 1–5 单周后虚增第3周。
4. Classic EAMS 支持已有课表原文、同源 frame、相对 endpoint 保留 WebVPN 前缀、
   至多3个参数候选、南开自动入口、HTTP/会话失效/超时明确失败。
   沿用源 ids/semester 正则原文；隐藏域使用 DOM，修正源正则把 value 错放在 `>` 之后的问题。
5. 所有1402候选保留 unverified/grad_unverified、enableFetch=false；三校按审计独立处理。
   南开仅补显式 supported（旧 nil 已同义），fetch=false；宁波仅纠正 classic_eams，
   unverified/false；佳木斯 unverified/false，不删除 status 假提升。

## 共享接线

见 `docs/catalog-v1063-shared-wiring.md`。App target、WebView capture 分派和首次加载 UA、
资源 folder reference 由主会话负责；这些未完成前不得宣称 App 端端到端可用。

## 静态对账（2026-11-04）

只读取 JSON/Git 做数据对账，未运行编译或测试：

- 4140 条，原 catalogId 集合保持；稳定身份按 UTF-8 排序换行连接 SHA-256：
  `655c88d589bbebd3ab86456605585f07befba578393e8f82c0fea76230843876`。
- 1402 条候选全部迁入：549 已有协议、810 jw_home、43 sg_asset；本科1354、研究生48。
- 全目录 pending/grad_pending 仍1260；相对 v1.0.62 有1404条实际变化（佳木斯保留原值）。
- 相对 v1.0.63 仅3校字段差异：南开 enableFetch=false；宁波 unverified/false；
  佳木斯显式 unverified/false。没有其他上游条目差异。
- vendor 导入284文件：282 JS + manifest + MIT；manifest 265校。
  当前43个 sg_asset 校名全部精确命中首个 adapter，无缺失匹配。

## 线上 CI 命令与验收

在 hosted macOS runner 准备真实 SwiftSoup checkout 后：

```sh
python3 scripts/tests/run_kingo_integration.py \
  --swiftsoup "$SWIFTSOUP_CHECKOUT" \
  --package-dir "$RUNNER_TEMP/jw-catalog-v1063" \
  --catalog
```

`--catalog` 包含原51项、home4项、拾光 parser4项、拾光 JavaScriptCore bridge5项、
classic EAMS5项、目录3项、状态7项，共79项。原有51项的历史通过不继承为本轮结果。
测试副本仅替换 Bundle 查找为 SwiftPM Bundle.module；生产源码原样编译。

CI 应同时验证主会话 Xcode 工程：新源码 target 注册、folder assets 布局和
真实 WebView 分派/桌面 UA。独立 harness 不含 SwiftUI WebView coordinator，
不证明 WKWebView 抓取、登录有效性、43校原脚本现场兼容或整个 App 可构建。

新增回归覆盖：
- 入口 sentinel 不抢候选、真实 Kingo 自动识别、登录页/显式协议分派。
- 拾光字段与稀疏周精确映射、非法/自定义时间拒绝、其他 JSON 协议不误抢。
- JavaScriptCore 执行真实桥：先课程后元数据、完成/异常/组合课表失败、
  超时一次回调、重复导入新状态、manifest NFKC 精确校名。
- 三校 fixture 解析及登录/空壳反例、NBCC exact-host UA、跨语言 regex invariant。
- 全4140身份摘要、1402候选逐条精确元数据、43实际资产加载与MIT许可、55 Registry工厂。

既有 `JwCatalogueTests` / `JwParserTests` 的资产规模断言按本次已审计目录更新为2880入口，
并分开锁住2482本科未验证、48研究生未验证；未删除测试或放宽计数。
它们依赖完整 App，不计入上述79项，随主会话 Xcode CI 执行。
