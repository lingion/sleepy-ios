# WakeUP v6.1.70 在线分享协议切片

## 先行证据与范围

源代码基线来自 `/Users/kerrylee/sleepy`：

- `app/src/main/java/com/lingion/sleepy/data/jw/WakeUpShareClient.kt`：两段 POST、15s 超时、请求头、五段 JSON 转换。
- 同目录 `WakeUpShareProtocol.kt`：v6.1.70 公开协议常量、signA/signB、签名排序串、RC4 key。
- 同目录 `WakeUpV6170Crypto.kt`：私有 DES（LSB-first，PC2 重复索引）与末字节长度填充，不能换成标准 DES。
- `app/src/main/assets/third_party/shiguang/js/GLOBAL_TOOLS/wake_up.js`：拾光源脚本，注释说明参数提取自 WakeUP v6.1.70 官方渠道 APK；这是第三方兼容实现证据，非官方公开 SDK 文档。
- `app/src/test/resources/jw/wakeup/vectors.json`：Android 已保存的 vendor JS 金标；iOS 测试逐字引用固定 MD5/DES/RC4/signA/signB/请求体，未在本机生成新期望值。
- `WakeUpLiveCrossVerifyTest.kt` 记录 Android 的历史活体验证，但本切片没有运行或重复调用真实服务。

HTTP fixtures 使用上述固定 signB 和合成课表，测试通过注入 transport 完整替代网络；传输回归不使用真实课表/真实分享码。网络生产实现用 URLSession，取消任务传递到底层请求。

## 导出协议阻塞

指定的三个 Kotlin 文件及 vendor JS 仅定义 `/pluto/app/antispam` 和 `/share_schedule/getv2`。未发现创建分享码的 URL、请求 schema、签名明文或响应 fixture。Android `ScheduleExporter.exportWakeUpShareText` 是本地文本，不是分享码上传。不能从 getv2 猜测 upload/create 接口。

另只读查询了作者公开仓库 `https://api.github.com/repos/YZune/WakeUpSchedule`：元数据的 `pushed_at` 为 `2018-04-07T01:28:19Z`，不能据此声称已经找到 v6.1.70 的创建分享码协议。旧猜测仓名 `WakeUpSchedule_Kotlin` 返回 404。

生成服务端分享码与导出 sheet 必须等主会话提供可信上传协议源码/HTTP fixture 后实现；本切片不增加假成功或空壳按钮。

## 已写入文件 / 工程登记

新增以下生产文件到 **Sleepy App target**（不需要给 Widget/Watch 增加网络入口）：

- `Sleepy/data/share/WakeUpV6170Crypto.swift`
- `Sleepy/data/share/WakeUpShareProtocol.swift`
- `Sleepy/data/share/WakeUpShareClient.swift`
- `Sleepy/ui/screen/imports/WakeUpShareImportSheet.swift`

`WakeUpShareURLSessionTransport` 使用独立 ephemeral session、15s 超时、流式 4 MiB 上限、取消传递及同主机 HTTPS 重定向约束。协议层不依赖 AppPrefs，读取服务不会写本地课程；不记录分享码/token/签名。返回 200 仍检查 JSON/body/errNo，空 shareData 不转成可成功导入的空课表。数值 nodes 大于 10000 显式拒绝，避免不受限展开。

按主会话追加指令，`Sleepy/ui/screen/mine/ExportScreen.swift` 的 ICS 导出已传入：

```swift
ScheduleExporter.exportIcsOrThrow(table, courses,
    transfers: AppPrefs.shared.getHolidayTransfers(table.id))
```

这里使用导出选择器解析出的 `table.id`，不是主页当前选中 id。其他导出路径原样保留；未改 parser/exporter 或 AppPrefs。

## ImportSheet 接线契约（主会话）

直接接口：

```swift
try await WakeUpShareClient().fetchScheduleJson(inputText)
```

返回值是标准 WakeUp JSON，可直接传给既有 `ImportSheet.buildImportPreview(json, viewModel.state, onError:)`。此时尚未修改任何本地课表；沿用原预览、冲突确认、五种导入模式和撤回批次。

专属 sheet 接口：

```swift
WakeUpShareImportSheet(
    initialText: inputText,
    onResolved: { json in
        pendingWakeUpJSON = json
        ImportSheet.dismissKeyboard()
        showWakeUpShare = false
    },
    onCancel: {
        pendingWakeUpJSON = nil
        showWakeUpShare = false
    }
)
```

`pendingWakeUpJSON: String?` / `showWakeUpShare: Bool` 由父页面持有；每次打开前清空 pending。**在该子 sheet 的 `.sheet(..., onDismiss:)` 回调中**取走并清空 pending，再调用 `buildImportPreview` / 赋值 `preview`。不要在 `onResolved` 中直接同时弹预览 sheet，以免两个 sheet 交叠。用最新 `viewModel.state` 生成预览，而不是请求启动时的旧 state。

取消按钮或滑动关闭会停止请求；即便 transport 延迟结束，generation + Task 取消校验会阻止陈旧结果进入预览。显式关闭调用 `onCancel`；系统滑动关闭交由父 sheet 的 dismissal 状态处理。

已有粘贴/外部分享入口可先用 `WakeUpShareClient.looksLikeShareCode(text)` 做窄窗路由：裸 8–200 位口令，或带“分享口令”且可提取合法值的文案走线上。既有 JSON、ICS、HTML、sleepy-v1 继续走原解析。三个触发点需一起核对：粘贴预览、文件/外部内容读入、`consumePendingImportText()`。本代理没有编辑 ImportSheet。

## 测试与 fixtures

加入 **SleepyTests target**：

- `SleepyTests/WakeUpShareFixtures.swift`（仅测试数据，不是测试类，不需要 Copy Bundle Resources）
- `SleepyTests/WakeUpV6170CryptoTests.swift`：7 项。
- `SleepyTests/WakeUpShareClientTests.swift`：9 项。

CI 选择：

```text
SleepyTests/WakeUpV6170CryptoTests
SleepyTests/WakeUpShareClientTests
SleepyTests/FixedDateImportExportTests
```

共 16 项新测试：vendor 固定密码学向量、完整请求体逐字节、两段请求头/路径/超时、服务错误、非 JSON、错误签名、损坏密文、过期空 shareData、五段转换、原 parser 接收、网络/界面取消、超限响应。`encryptedResponse()` 是用于传输编排的合成 fixture，使用已由独立金标约束的 RC4 原语生成；没有把自生成密文当成密码学金标。

## 新 UI keys（全局资源由主会话汇总）

| Key | 中文 fallback |
| --- | --- |
| `wakeup_share_import_title` | 导入 WakeUP 分享口令 |
| `wakeup_share_import_hint` | 粘贴 WakeUP 分享口令或完整分享文案，联网获取课表后预览。 |
| `wakeup_share_input_label` | WakeUP 分享口令 |
| `wakeup_share_fetching` | 正在获取分享课表… |
| `wakeup_share_cancel_request` | 取消请求 |
| `wakeup_share_fetch` | 获取并预览 |

错误枚举保留上游中文描述，后续主会话可统一资源化。来源归属继续沿用项目现有拾光致谢；没有复制或运行完整第三方 JS。

## 验证状态

本机未编译、测试、启动模拟器或运行 swiftc；未发送任何真实分享服务请求；未提交/推送或再派代理。源码已静态对照，`git diff --check`（新增文件用 `--no-index`）未报告空白错误，新增测试尚待线上 CI。服务端分享码**导出仍明确阻塞**，不能把本切片记录为导入导出全量对齐。
