# 教务迁移共享接线契约（交主会话）

本子任务只编辑 data/jw、教务资源、Jw 测试与独立 harness。以下共享文件由主会话接线。
本轮所有新增代码/测试均未在本机执行，须线上 CI 验证。

## JwWebViewLoginScreen.swift

1. `capture()` 中，在通用 ZF/WebVPN 猜型之前派发：

   ```swift
   if school.type == JwProtocol.TYPE_SG_ASSET {
       do {
           coordinator.evaluateFetchWithTimeout(try JwSgAssetBridge.bridgeJs(schoolName: school.name))
       } catch {
           showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
               matchedAnchors: [], status: .unknown), error.localizedDescription)
       }
       return
   }
   if school.type == JwProtocol.TYPE_CLASSIC_EAMS {
       coordinator.evaluateFetchWithTimeout(JwClassicEamsFetch.js)
       return
   }
   ```

   两个脚本直接使用现有 WK `__sleepyBridge.postMessage({json: ...})` 通道，回调由
   `handleWiseduResult` 交原 school/type 给解析器。脚本内置最终回调超时闸，拾光 120 秒，
   classic EAMS 20 秒；evaluateJavaScript 的同步返回不能视为异步抓取已完成。
   如重构 coordinator 超时，必须以桥消息为完成信号；不要另加 20 秒闸截断拾光。

2. `desktopUa` 初值用 `JwClassicEamsFetch.initialDesktopUa(school)`。可新增本 View 显式
   initializer 保持所有既有参数默认值，或在主会话的统一 WebView 初始配置处接线。
   必须在第一次 load 前设置 desktop UA；仅 onAppear 改 State 可能晚于页面加载。
   宁波仍是 unverified/false，但用户主动进入时需要 PC 入口，因此 UA 判定按校名对应的
   exact URL host + classic_eams，不把 enableFetch 当作已认证证据。

## 工程与资源

- 注册本轮新增 `Sleepy/data/jw/JwHomeParser.swift`、`JwSgAssetParser.swift`、
  `JwSgAssetBridge.swift`、`JwClassicEamsFetch.swift` 到 App target。
- `Sleepy/resources/third_party` 必须作为保留层级的 folder resource 复制（不能扁平化
  282 个脚本，否则重名与 manifest 路径失效）。`JwSgAssetBridge` 从
  `Bundle.main.resourceURL/third_party/shiguang/manifest.json` 查找。
- 新增 Jw 测试及 `SleepyTests/resources/classic_eams`、
  `docs/catalog-v1063-candidates.json` 加入测试 target（后者仅测试资源）。
- `JwSchoolStatusRegressionTests` 的 Registry 契约将由本子任务更新至 55 项；
  已静态查看 `scripts/jw-school-status-check/run.py`：集合从实际测试抽取，未硬编码53，
  不需要改该脚本。

## 状态策略

1402 条严格保留 unverified/grad_unverified 与 enableFetch=false；南开显式 supported
只等价于旧缺省状态，fetch 保留 false；宁波纠正 classic_eams 但保留 unverified/false；
佳木斯保留 unverified/false。新增能力与 CI fixture 通过均不代表 iOS 真实登录验证。

## 许可显示

拾光 MIT 原文随 assets 导入；来源和维护者保留在原 manifest。LicenseScreen 已有拾光
条目（主会话其他 WIP），请确保可见致谢为 ShiGuangSchedule/shiguang_warehouse / 星河欲转 / MIT，
并包含 `third_party/shiguang/LICENSE-MIT.txt`。不需覆盖现有其他致谢。
