# iOS Debug Console：最小原生控制面与共享接线

## 当前交付状态

新增 `Sleepy/debug/` 原生控制面及两组 DebugConsole 测试；共享时钟已移到
`Sleepy/util/AppClock.swift`。本轮已接设置页、DateUtils、ScheduleViewModel、TodayScreen、
CourseTableView；追加授权后已接 `JwImportViewModel.loadSchools` 与
`UcasDetailFetch.fetchOne`。App 壳启动/注入仍待主会话接入。
**尚未本机编译、运行测试、启动模拟器；以下测试和命令仅供线上 CI。**

实现沿用 Android `console/` 的 URL、token header、JSON envelope 与数据字段，传输换为
Apple `NWListener`。未引入第三方服务框架。主会话完成下述接线且 CI 通过前，不应标记
“控制台已端到端验收”。

## 1. App 壳接线（主会话已写入，待云端验收）

### 1.1 AppDelegate 初始化与生命周期

`Sleepy/SleepyApp.swift` 的 `AppDelegate` 已新增 DEBUG 属性：

```swift
#if DEBUG && !WIDGET_EXT && !WATCH_APP
@MainActor
lazy var debugConsole = DebugConsole(
    repository: repository,
    root: rootViewModel,
    catalogConsumerWired: true,
    nativeMockConsumerWired: true
)
#endif
```

时钟消费方现已接入，组件默认回调会重算周次并通知根 VM/课表 VM 重绘，不需 App 壳再写
同一回调。第 5 节两处消费者现已接入，初始化应同时传上面的两个 `true`。
构造器缺省仍是 false；主会话须显式传入才能启用对应写入/消费能力。

已在 `application(_:didFinishLaunchingWithOptions:)` 中、返回 `true` 前调用：

```swift
#if DEBUG && !WIDGET_EXT && !WATCH_APP
debugConsole.start()
#endif
```

`applicationWillTerminate` 已调用 `debugConsole.stop()`。组件自身已观察后台/前台通知：

- 后台：停止 listener、关闭所有连接、清路由、撤销 token、重置虚拟时钟。
- 前台：仅当用户仍保持启用时重新监听，并产生新 token。
- 用户停用：`enabled=false`，以后前台通知不会再次启动。
- 监听失败：显示失败状态并撤销 token；不显示“已监听”。
- 启动中重复前台通知不会重复创建 listener。

### 1.2 设置入口与实例传递

`WindowGroup` 内已用同一个 `AppDelegate.debugConsole` 注入根树：

```swift
#if DEBUG && !WIDGET_EXT && !WATCH_APP
AppRoot()
    .environmentObject(appDelegate.rootViewModel)
    .environmentObject(appDelegate.debugConsole)
#else
AppRoot()
    .environmentObject(appDelegate.rootViewModel)
#endif
```

`GeneralSettingsScreen.swift` 已增加 DEBUG environment object 和实验室下方启停 Section，
实际容器是 ScrollView/VStack，不是 Form。上述根实例注入已写入；监听与设置交互仍待线上验证。

Debug preview/独立呈现设置页也须提供这个 environment object。Release 没有此属性、
设置行、监听器、token store、router 或 handler；不移植 Android Release 连点解锁入口。

### 1.3 虚拟时钟的最小业务消费方

`Sleepy/util/AppClock.swift` 提供 `AppClock.now: Date`。下列替换本轮已完成：

| 文件 | 替换点 |
|---|---|
| `Sleepy/util/DateUtils.swift` | `semesterStatus/currentWeek/todayDayOfWeek/isDateToday` 的默认 `Date()` 改为 `AppClock.now` |
| `Sleepy/ui/screen/schedule/ScheduleViewModel.swift` | `loadCourses` 的 `WeekDisplayResolver.resolve(now:)`、`createEmptyTable` 的 `let now`、`recalculateWeekDisplay` 的 `now:` 改为 `AppClock.now` |
| `Sleepy/ui/screen/today/TodayScreen.swift` | body 内 `let today = Date()` 改为 `AppClock.now` |
| `Sleepy/ui/component/CourseTableView.swift` | 两处 `todayDate: Date = Date()` 的缺省值改为 `AppClock.now` |

`recalculateWeekDisplay()` 已是现有业务重算入口；保留用户手动选周语义。
`testBusinessWeekAndTodayConsumeVirtualClock` 专门验证 DateUtils 消费方，待线上执行。

此最小接线验证的是课表周次、今天页、当天标记和新表日期。通知调度、日期选择器等其余
直接取 `Date()` 的业务面尚不计入虚拟时钟覆盖；token TTL、HTTP 超时和审计时间始终使用
真实/单调时间。widget/watch 是独立进程，不继承 App 内的内存偏移。

### Target membership

`project.yml` 的主 app 已递归包含 `Sleepy`，测试已递归包含 `SleepyTests`，线上
`xcodegen generate` 会收录新文件。主会话已对 widget/watch 排除整个 debug 目录；所有
执行文件额外使用 `#if DEBUG && !WIDGET_EXT && !WATCH_APP`。
两处教务消费者也使用相同 guard；当前 `project.yml` 明确 widget 的条件为 `WIDGET_EXT`，
watch 两个 target 均为 `WATCH_APP`，不能只用 `#if DEBUG` 引用 debug 目录类型。
`AppClock.now` 在 Release/widget/watch 恒返回真实 Date。若某个共用 DateUtils 的 target
采用逐文件 source 清单，须同时加入 `Sleepy/util/AppClock.swift`。共享时钟已不在排除目录。

## 2. 协议与当前能力

固定监听 `127.0.0.1:3737`，通过 `requiredLocalEndpoint` 绑定，另设 `acceptLocalOnly`。
未监听设备 LAN IP；真机从 Mac 调用须另建 USB 端口转发，模拟器可在 CI 上验证回环访问。

- 成功：`{"ok":true,"data":...}`。
- 失败：`{"ok":false,"error":"...","code":N}`；HTTP status 同 N。
- `X-Sleepy-Token` 大小写不敏感；仅 `/v1/hello`、`/v1/enable` 免 token。
- 未知路径也先鉴权：无/错/过期 token → 401，通过后未知路径 → 404。
- 32 字节 `SecRandomCopyBytes` → 64 hex，内存保存，24 小时单调计时；后台/stop 撤销。
- Debug `POST hello` 返回 token 与能力；`POST enable` 仍要求 `passphrase` 字符串，返回
  `ALREADY_ACTIVE`，与上游 Debug 分支一致。
- 无 CORS；带 `Origin` 或 `Sec-Fetch-Site` 的网页来源请求拒绝，避免本机网页读取 Debug token。
- HTTP 单连接单请求；16 KiB header、1 MiB body、最多 8 个客户端、10 秒连接总时限。
  重复 header、Content-Length 歧义、chunked、流水线拒绝。socket 回调切主线程且复核
  generation/deadline，停用前排队的旧请求不会在新会话执行。
  时限用于连接/收发等待；stop/超时取消该请求 Task。不能中断已经进入 repository 的同步
  操作，也不回滚已进入真实 NotificationScheduler 的重排（该 API 不提供可撤销事务）。

| 端点 | 能力 |
|---|---|
| POST `/v1/hello`, `/v1/enable` | 探活、token、Debug 启用协议 |
| GET/POST `/v1/clock` | offset(deltaMs/dayOffset)、absolute(epochMs/dayOffset)、reset；偏移随真实时间流逝，非冻结时间 |
| GET `/v1/data/tables` | 全部表、课程、有效作息、全部作息表和默认表 ID |
| POST `/v1/data/table` | create/update/delete/setDefault；真实 repository |
| POST `/v1/data/course` | entity 数组、text、b64、sandbox 内 path、clipboard；真实 ScheduleParser/分组写入 |
| POST `/v1/data/timesetting` | create/update/delete；复用 savePeriodTable 和绑定删除守卫 |
| GET/POST `/v1/data/prefs` | app persistent domain；flat string/number/bool/null；console_ 整批拒写、导出排除 |
| POST `/v1/data/catalog` | get/set store 与列表/搜索索引消费者已接；待 App 壳传 wired flag 和线上验证 |
| GET/POST/DELETE `/v1/jw/mock` | 持久规则与 UcasDetailFetch 回放已接；待 App 壳传 wired flag 和线上验证；不是全 WebView 回放 |
| POST `/v1/trigger` | 8 个 type/别名有原生执行体；4 个 FluidCloud type unsupported，见第 6 节 |
| GET `/v1/log?limit=N` | 200 条双环：已埋点控制台业务事件 + HTTP 审计；不是所有 NSLog |
| POST `/v1/session/reset` | 只删 `console:` 前缀课表、重置时钟、清 catalog/mock 持久层；`importDraftsCleared=false` |
| GET `/v1/ui/tree` | 当前 key window 的 UIKit/公开 accessibility container 节点、dump、fingerprint |
| POST `/v1/ui/find` | 六判据 AND；index 取匹配序位，负数/越界空命中 |
| POST `/v1/ui/action` | 原生 activation、UITextField/UITextView 输入、UIScrollView 滚动、根导航/返回 |
| GET `/v1/ui/screenshot` | 当前 key window PNG，`format/bytes/image`，不捕获其他 App 或系统屏幕 |

数据数组在任何写入前全部解码、校验；全部自带非空 groupId 时走 KeepingGroups，否则
走 repository 认亲。实体 id/tableId 不允许覆盖外层目标。字段校验还限制 weeks/nodes 到
1…1000，避免病态数据进入日程派生。

文本导入沿用上游“insertTable → insertCourses”顺序，不调用强制设默认表的
`importNewTable`。因此 **参数/解析失败为零写入，但后续数据库异常不提供跨两次 repository
操作的事务保证**。证据：Android `DataOpsHandlers.kt:245–262` 先 `insertTable` 再
`insertCourses*`，`TriggerHandler.kt:113–127` 的 import_helper 同样分两步。成功后走既有数据刷新 hook；insertTable 和
insertPeriodTable 自身没有 hook，因此控制台补调现有 hook，未旁路 SQL。

Prefs 写入主题 key 使用现有 setter 通知 Combine；其他 flat key 写实际 UserDefaults 并
发送 didChange。仅初始化时取值的页面未承诺热更新。与 Android 不同，nested JSON 不会
被暗中字符串化，返回 400；所有类型检查在第一笔写入前完成。

## 3. UI 平台差异和实际控制方式

selector 字段：`testTag/text/textContains/className/role/clickable/index`。
`testTag` 映射 iOS `accessibilityIdentifier`，node 输出保持上游 `tag` 字段。
坐标为 window **points**；截图像素受屏幕 scale 影响。

```json
{"action":"navigate","target":"today"}
{"action":"navigate","target":"general"}
{"action":"back"}
{"action":"tap","selector":{"testTag":"fixture.save"}}
{"action":"input","selector":{"role":"TextField","index":0},"text":"console:课程"}
{"action":"scroll","selector":{"role":"ScrollView","index":0},"direction":"down","amount":400}
```

`navigate` 是 iOS 原生补充动作，调用当前根 VM/navigator，不生成虚拟 UI 节点。
支持四 tab：schedule/today/manage/mine；无参数页面：general/allTables/courseList/
periodTables/appearance/about/reminder。已打开 overlay 时须先 back 再打开其他页面。
`back` 限根 overlay，复用 pendingNew 丢弃链；系统 sheet/NavigationStack 内层不冒充已返回。

SwiftUI 只有公开 AX container 实际暴露的节点能进入 tree；不能保证任意 SwiftUI 文本和
自绘控件都可操作。没有 activation 的对象返回 501；任意坐标 tap、longTap/doubleTap/
swipe/drag/home/recents/key 也返回 501。没有私有 HID/UIApplication 注入。
`action` 返回即时指纹 diff 和 `settled=false`，表示命令已派发，不代表 SwiftUI 下一帧
已渲染；调用方应轮询 tree 断言目标状态，再截图。

系统手势/按键、Android FluidCloudService、全 WebView HTTP(S) 拦截和全清 import drafts
仍未实现。`hello.capabilities.jwMock=false` 恒明确完整 WebView 回放不可用；局部原生回放
另报 `jwMockNativeHTTP`。返回 501 的动作不计入“已实现”或“验收完成”。

## 4. 线上验证

仅由线上 runner 执行（本切片没有执行以下命令）：

```sh
xcodegen generate --spec project.yml
xcodebuild build-for-testing -project Sleepy.xcodeproj -scheme Sleepy \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project Sleepy.xcodeproj -scheme Sleepy \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -only-testing:SleepyTests/DebugConsoleTests \
  -only-testing:SleepyTests/DebugConsoleCapabilityTests \
  -resultBundlePath build/ci/debug-console.xcresult CODE_SIGNING_ALLOWED=NO
```

既有 `.github/workflows/ios-build.yml` 的 SleepyTests 步骤会自动包含该测试类。
测试覆盖：逐字节边界 UTF-8 HTTP 分帧、请求歧义拒绝、未知路径鉴权、TTL/撤销、网页来源
拒绝、clock 叠加及业务消费者、非法课程批次零写入/权威分组、保留 prefs 键整批拒绝、
session reset 保留用户表、selector AND/index、真实 UIButton action/PNG 签名、真实
loopback HTTP envelope/撤销与未完成请求超时。新增能力测试覆盖 catalog 持久化/失败不改内存/
整行 patch 替换、mock 首规则优先/HTTP status/headers/body/路径逃逸/停用、日志脱敏/容量、
trigger 等待调度器/unsupported 零写入/虚拟时间建课与清理、DELETE 和 query 解析。

线上 App 场景还需验收：

1. Debug 冷启动 POST hello → token；GET tables 得到真实当前库。
2. POST table 建 `console:ci` → POST course → navigate schedule/today，断言 UI 显示。
3. clock absolute/dayOffset → tree/截图证明周次、当天标记和今日课程变化。
4. 设置页 stop → 原有连接关闭、端口不再响应；前后台切换不会复活已停用控制台。
5. 再启用得到新 token；旧 token 401。启用时退后台端口关闭，回前台重发 token。
6. Release 构建可编译；App 启动后 3737 无监听、设置无 Console、产物无 ConsoleListener/
   DebugConsole/ConsoleRouter 执行符号。widget/watch 构建不包含执行入口。
7. 真实 SwiftUI 节点可见性/activation 和不同屏幕尺寸 PNG，在 CI/真机实际验证后填写结果。
8. catalog：给原本空 URL 的学校 set http(s) URL，验证列表与搜索可见；变更 status/type 后
   退出重进教务页验证新值；stop 后等列表重载完成确认恢复 base，重新启用恢复持久覆盖。
9. UCAS：注入匹配详情 URL 的 200 响应（含非 UTF-8 charset），通过真实 fetchOne/enrich
   验证正文解码；非 200 仍走失败降级，未命中/停用仍走真实请求。不得只验证 store.response。

控制台探活示例（线上已运行 Debug App/建立设备转发后）：

```sh
curl -sS -X POST http://127.0.0.1:3737/v1/hello
curl -sS -H "X-Sleepy-Token: $TOKEN" http://127.0.0.1:3737/v1/data/tables
curl -sS -X POST -H "X-Sleepy-Token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"action":"navigate","target":"today"}' http://127.0.0.1:3737/v1/ui/action
```

读取 JSON `ok/data` 和实际 UI/PNG 作为证据；不能仅凭 HTTP 200 认定功能通过。

## 5. 教务消费者接线记录（已落地，未运行验证）

### 5.1 Catalog：`Sleepy/data/jw/JwImportViewModel.swift`

1. 已增加 observer，init 注册，deinit 移除：

```swift
#if DEBUG && !WIDGET_EXT && !WATCH_APP
private var consoleCatalogObserver: NSObjectProtocol?
#endif

init() {
    #if DEBUG && !WIDGET_EXT && !WATCH_APP
    consoleCatalogObserver = NotificationCenter.default.addObserver(
        forName: ConsoleCatalogStore.didChange, object: nil, queue: .main
    ) { [weak self] _ in
        DispatchQueue.main.async { self?.loadSchools() }
    }
    #endif
    loadSchools()
}

deinit {
    #if DEBUG && !WIDGET_EXT && !WATCH_APP
    if let observer = consoleCatalogObserver { NotificationCenter.default.removeObserver(observer) }
    #endif
}
```

2. `loadSchools()` 已保留 base list 的解析与 cities map，将 URL 过滤移至覆盖之后。
   **覆盖必须先于空 URL 过滤**，否则无法替原本空 URL 的目录项提供测试入口。
   当前 `DispatchQueue.main.async` 发布块核心逻辑：

```swift
DispatchQueue.main.async {
    var effective = list
    #if DEBUG && !WIDGET_EXT && !WATCH_APP
    effective = ConsoleCatalogStore.shared.apply(to: effective)
    #endif
    let visible = effective.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    self?.schools = visible
    self?.searchIndex = SchoolSearchIndex(visible)
}
```

apply 放在发布时刻，防止后台读目录期间发生 stop/set 后把旧覆盖结果发布回来。
不改纯 `parseSchoolsJson`：测试/console base 读取必须保留未覆盖原始目录。
目录变化通知仅重载列表/搜索索引；已经打开并持有旧 school value 的 WebView 需退出重进。

3. App 壳初始化传 `catalogConsumerWired: true`。store 仅 console active 时套用，stop/后台
   停止套用覆盖，并通知列表异步重载回 base；持久覆盖保留到下次启用，session/reset 清掉。与上游一样按 name 匹配，只覆盖
   status/type/url，保留 `catalogId/enableFetch`；URL 另限制为 http(s)。

### 5.2 原生 HTTP mock：`Sleepy/data/jw/UcasDetailFetch.swift`

已将 `fetchOne` 的请求执行接入以下分支：

```swift
let data: Data
let response: URLResponse
#if DEBUG && !WIDGET_EXT && !WATCH_APP
if let mocked = ConsoleJWMockStore.shared.response(for: request) {
    data = mocked.0
    response = mocked.1
} else {
    (data, response) = try await session.data(for: request)
}
#else
(data, response) = try await session.data(for: request)
#endif
```

其后的 HTTP 状态检查、charset 解码及详情解析完全复用原链。然后 App 壳传
`nativeMockConsumerWired: true`。未命中/停用时调用真实 session。现存 WKWebView 导航、
JS fetch/XHR、iframe、下载抓包不经过此入口，因此不在覆盖范围；不会以 URLProtocol
注册成功冒充能拦截 WKWebView。若将来增加消费者，需要同步改 GET mock 的 replayScope。

mock 协议对齐 `JwMockHandler.kt` 和 `MockRuleStore.kt`：

- POST `url_pattern/respond_with(html|b64|file)/body/status/content_type/headers`。
- GET 返回 `rules`，每条含 `url_pattern/status/content_type/headers/body_bytes`，另报局部 scope。
- DELETE `{url_pattern}` 删除全部同 pattern；`{all:true}` 清空。
- 首条正则命中优先（substring search，不强制全 URL 匹配），重复 pattern 追加不覆盖。
- 持久文件位于 Application Support/DebugConsole；`file` 仅此目录内相对路径，拒绝
  `..`、绝对路径、符号链接逃逸。每条 ≤1 MiB、最多 100 条、合计 body ≤16 MiB。
- 与上游不同：iOS 写盘失败返回错误且不更新内存；不静默宣称规则已持久化。
- status/headers/body 作为原生响应送入消费方，不处理真实 Set-Cookie store 或跳转副作用。

## 6. 完整能力矩阵与证据边界

“实现”只表示代码路径存在；所有运行时行为均待线上 CI。AppDelegate 启动/实例注入仍是
整套 HTTP 服务的共同前置条件。下表 **不将 501 算作完成**。

| 能力 | 当前状态 | 尚缺/差异 |
|---|---|---|
| listener/router/auth/TTL/stop | 已实现，App 壳待接 | 线上 loopback/端口关闭/Release 产物验证未运行 |
| 设置启停 | 已接 GeneralSettingsScreen | AppRoot environmentObject 待主会话注入 |
| clock + 日期/周次/今日标记 | 已接业务消费者 | 通知引擎与其余直接 Date() 消费方未纳入虚拟时间 |
| table/course/timesetting/prefs | 已实现 | 文本导入非跨方法事务，prefs 复合值差异见上 |
| catalog get | 已实现 | 始终读真实目录；active+wired 时叠覆盖 |
| catalog set | store 与真实消费者已接，**待运行验证** | App 壳须传 catalogConsumerWired: true；set/stop 通知重载列表和索引 |
| jw/mock 规则 GET/DELETE | 已实现 | 如无活跃消费方，GET 明报 unwired |
| jw/mock POST + Ucas 原生回放 | store/response 与 fetchOne 已接，**待运行验证** | App 壳须传 nativeMockConsumerWired: true；仅 Ucas 原生 HTTP |
| jw/mock 全 WebView HTTP(S) | **未实现** | WKWebView 无公开等价拦截；hello.jwMock=false |
| trigger notification/before_class_alarm/schedule_before_class_now | 已实现 | await 真实 NotificationScheduler；其实际是未来 7 天重排；尊重偏好/权限，不证明系统已显示 |
| trigger sync/restore_and_cleanup | 已实现，上游同义 | `sync` 不是 watch/widget 同步，而是下面的清理逻辑 |
| trigger delete_non_default_tables | 已实现，上游同义 | 删除真实非默认表，不限 console: 前缀 |
| trigger add_soonest_course | 已实现，上游同义 | 创建默认“流体云触发测试”表和 ownTime 课；不表示 FluidCloud 能力可用 |
| trigger import_helper | 已实现 | 仅 text/b64；强制 repo 认亲，与上游 helper 相同；非原子 |
| trigger fluid_cloud/test_before_class/live_card/clear_fluid_notification | **未实现、501** | 项目无原生 FluidCloudService/Live Activity 实现，不以普通通知冒充 |
| log audit | 已实现 | 真 HTTP 请求审计；未知 path 统一 [unknown]；不记 body/query/token |
| log app | **局部已埋点** | 控制台 lifecycle/data/prefs/clock/trigger/catalog/mock/reset；未接全 App NSLog/教务业务日志 |
| session reset | 部分上游等价 | 清 console: 表/clock/catalog/mock；保留用户 prefs、其他表、import drafts 和日志 |
| UI tree/find/native action/screenshot | 已实现 | SwiftUI AX 覆盖和输入/截图需线上验证，不能宣称任意自绘节点可达 |
| 系统键/坐标手势注入 | **不支持、501** | 无私有 API，无假成功 |

### Trigger 上游精确行为

来源：`app/src/debug/java/com/lingion/sleepy/debug/console/TriggerHandler.kt:51–82`、
`debug/DebugTriggers.kt:34–53,90–135`：

- `sync/restore_and_cleanup`：先找第一张名字不含“测试”且不含小写 `fluid` 的表设默认；
  再删除名字含“测试”或“流体”的表。上游中英文判据不对称，本实现保留。
- `delete_non_default_tables`：删除全部非默认表。这两个 trigger 的破坏范围比 session/reset
  大，已按上游明确执行，不自动替换为仅清 console 表。
- `add_soonest_course`：以虚拟“今天”周一为 startDate，day=虚拟今天 weekday，startTime=
  虚拟现在+delayMin，endTime 再+45 分钟；start/endWeek=1/20，ownTime=true，建表设默认。
  与上游一样不会因 delay 跨午夜而迁移 day。iOS 额外限定 delayMin 为 0…10080。
- 三个课前提醒别名忽略传入的课程文案，只调用现有调度器；`notification` 不另造测试通知。
- import_helper 的 teacher/group 等行为由 parser/repository 认亲决定，不使用 data/course
  中“全部显式 groupId 即权威”的捷径。

### Log 与取消语义

两环各 200 条、旧到新，`limit` 为正整数时各取尾部 N；无效/非正值按全环（上游同义）。
app 事件使用固定枚举文本，避免泄露 courseName/path/token/body；审计省略上游 tokenSuffix。
HTTP 对 `/v1/log` 自身的审计在生成本次快照后追加；router 单测直调不伪造 HTTP 审计。
stop/reset 不清日志。异步 trigger 在调度器完成后才回结果，不把 Task 创建成功当执行成功；
连接关闭/stop 取消 Task 并阻止旧响应发送，但不声称能回滚已调度的系统通知。
