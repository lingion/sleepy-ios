# Spec: Sleepy iOS — sleepy 课程表 100% 移植 (Android → iOS)

**源项目**: `~/Desktop/sleepy` (Kotlin + Compose, 87 文件 / 18,242 行, v1.0.34, GPL-3.0)
**目标**: SwiftUI 等价移植,AltStore Classic 免费账号侧载,自用分发。

---

## Objective

把 sleepy 课程表**逐文件、逐函数忠实翻译**成 iOS 原生 app。移植=翻译,不是重写:每个 Kotlin 文件有对应 Swift 文件,每个函数有对应函数,strings.xml 每条字符串逐条搬运,数据流/交互逻辑不变。仅当功能依赖 Android 平台私有机制且 iOS 无对应物时做等价适配(见「平台差异映射表」),适配不等于省略——UI 与行为仍完整。

验收者 = 用户本人,iOS 26 真机 + AltStore 侧载。

## Tech Stack

| 项 | 选择 | 理由 |
|---|---|---|
| 语言 | Swift 5.8 | Xcode 14.3.1 自带 |
| UI | SwiftUI (iOS 16.4 SDK) | 部署目标 iOS 16.0,iOS 26 设备兼容 |
| 持久化 | GRDB 6.x (SPM) | Room 最自然对应;无 SwiftData(Xcode 14 无) |
| Widget | WidgetKit | 5 类 widget 全移植 |
| 网络 | URLSession 内置 | 教务直连导入 |
| WebView | WKWebView | JW 登录取 cookie |
| 工程生成 | XcodeGen | project.yml 可读可 diff,免手写 pbxproj |
| 签名 | **不签名构建** → AltStore 用免费 Apple ID 重签 | 侧载标准做法;App Group 由 AltStore 注入 |
| 分发 | unsigned IPA 本地文件 → AltStore 安装 | 自用,更新=重新侧载 |

依赖经 SPM 拉取,git 源走 `gh.qdp.qzz.io` 镜像替换 `github.com`。

## Commands

```bash
# 生成 Xcode 工程(改 project.yml 后必跑)
xcodegen generate

# 构建+打出无签名 IPA(主命令)
./scripts/build-ipa.sh            # → build/Sleepy-unsigned.ipa

# 单元测试(移植自 Android test 源集)
xcodebuild test -project Sleepy.xcodeproj -scheme Sleepy -destination 'platform=iOS Simulator,name=iPhone 14'

# 模拟器跑主 app
open Sleepy.xcodeproj             # Xcode 14.3.1, iOS 16.4 simulator
```

## Project Structure(镜像 Android 包结构 1:1)

```
sleepy-ios/
├── project.yml                    # XcodeGen 定义(app + widget ext 两 target)
├── scripts/build-ipa.sh           # archive→无签名IPA
├── Sleepy/
│   ├── SleepyApp.swift            ← SleepyApp.kt
│   ├── MainActivity.swift         ← MainActivity.kt (导航壳/生命周期)
│   ├── data/
│   │   ├── AppDatabase.swift      ← AppDatabase.kt (GRDB)
│   │   ├── dao/                   ← dao/ (CourseDao, TimeTableDao)
│   │   ├── entity/                ← entity/ (CourseEntity, TimeTableEntity)
│   │   ├── jw/                    ← jw/ 全部 14 文件(协议解析+登录)
│   │   ├── parser/                ← parser/ (ScheduleParser 738行, ScheduleExporter)
│   │   └── repository/            ← repository/ (ScheduleRepository)
│   ├── ui/
│   │   ├── component/             ← component/ (PillNavigationBar, SegmentedSwitcher, DateTimePickers, ImportSheet, CourseDetailSheet, CourseTableView, SmartPeriodEditor, TimeSlotEditor, UpdateChangelogDialog…)
│   │   ├── screen/                ← screen/ (ScheduleScreen 三视图, TodayScreen, MineScreen, ManagementPage, AllTablesScreen, EditTableScreen, AddCourseScreen, ExportScreen, ReminderScreen, AppearanceScreen, GeneralSettingsScreen, AboutScreen, SchoolSelectScreen, JwWebViewLoginScreen…)
│   │   └── theme/                 ← theme/ (Theme, ThemePresets 5 预设+HSV)
│   ├── util/                      ← util/ 全部 9 文件 (AppPrefs, CourseColorUtil, DateUtils, LocaleHelper, PinyinMatcher, TimeTableUtils, UpdateInfo, UpdateManager, VersionUtils)
│   ├── widget/
│   │   ├── WidgetBundle           ← 5 widget 入口(Today, TwoDay, WeekList, WeekView, WeekGrid)
│   │   └── *Layout.swift          ← WidgetBitmapRenderers.kt 的布局逻辑→SwiftUI(见平台差异表#5)
│   └── resources/
│       ├── Localizable.strings ×5 ← values/{,zh-rCN,zh-rTW,ja,es}/strings.xml 逐条搬运
│       └── Assets.xcassets        ← 图标/主题色
├── SleepyWidget/                  # Widget Extension target
└── SleepyTests/                   ← androidTest/test 源集逐用例移植
```

## Code Style(翻译规范)

Kotlin → Swift 逐行对译,保结构:

```swift
// Kotlin:                        →  Swift:
// fun weekIndex(date: LocalDate): Int  func weekIndex(_ date: Date) -> Int
//    if (date < startDate) return -1        if date < startDate { return -1 }
//    ...                                    ...
```

- 命名:Kotlin camelCase 保留;`data class` → `struct`(Codable);companion → static/enum namespace
- 注释:原文注释一并翻译保留,不删不并
- 字符串:🚫硬编码——全部走 `L10n.key`(对应 R.string),五语言逐条
- 测试:Android 现有 8 个测试文件(JwParserTest, JwNewZfParserTest, JwWiseduParserTest, DateUtilsTest, CourseColorUtilTest, SmartPeriodConfigTest, VersionUtilsTest, ExportImportRoundTripTest, StringsKeyParityTest, UpdateInfoParseTest)的**每个用例**移植为 XCTest

## Testing Strategy

- 框架:XCTest,Xcode 内置,零新依赖
- 位置:`SleepyTests/`,文件名与 Android test 一一对应
- 覆盖:解析器(WakeUp/ICS/CSV/HTML/纯文本/教务 JSON)、日期周次计算、黄金角色彩、智能节次推算、版本比较、导入导出往返、字符串键五语言 parity(直接移植 StringsKeyParityTest 思路)
- 每完成一个 data/ 文件移植 → 立即跑对应测试 → 绿了才进下一个(UI 层 XCTest 为主,真机验收靠用户)

## Boundaries

- **Always**: 移植前先 Read 对应 Kotlin 原文件全文 · 每文件移植完跑测试 · GPL-3.0 保留原版权头
- **Ask first**: 删/跳过任何源文件或函数(哪怕看似无用)· 增第三方依赖 · 改 Room→GRDB schema 语义
- **Never**: 概括式重写("反正功能就是…")· 静默改交互行为 · 提交任何 Apple ID/证书信息 · 破坏 sleepy Android 仓库

## 平台差异映射表(唯一允许的"非逐行"处)

| # | Android 机制 | iOS 等价适配 | 性质 |
|---|---|---|---|
| 1 | AlarmManager 精确闹钟+BootReceiver | UNUserNotificationCenter 本地通知(UNCalendarNotificationTrigger),iOS 重启后通知仍持久,BootReceiver 不需要;64 pending 上限→按天批量排程 | 等价 |
| 2 | REQUEST_INSTALL_PACKAGES 自装 APK 更新 | UpdateManager 保留版本检查+UpdateChangelogDialog 完整移植,安装动作改为「提示重新侧载 IPA」 | 等价(动作降级) |
| 3 | OPPO Fluid Cloud(FluidCloudService + oppo-fluid-cloud-upk) | 🚫无 iOS 对应物,**整体跳过**,spec 里显式记录 | 平台私有 |
| 4 | ACTION_VIEW json 文件导入(ImportReceiverActivity) | CFBundleDocumentTypes + onOpenURL,ImportSheet 预览流程原样 | 等价 |
| 5 | RemoteViews+Canvas bitmap 渲染 widget | WidgetKit SwiftUI 视图;WidgetBitmapRenderers.kt 的**布局/排版/配色计算逻辑逐函数移植**,bitmap 管道本身不移植 | 等价(渲染载体换) |
| 6 | APPWIDGET_UPDATE 广播刷新 | WidgetCenter.reloadAllTimelines + WidgetKit timeline 策略 | 等价 |
| 7 | PinWidgetActivity/WeekGridPreviewActivity | WidgetBundle gallery 静态预览描述 | 等价 |
| 8 | Room(SQLite) | GRDB,表结构/D	sql语句语义保持 | 等价 |
| 9 | AppPrefs(DataStore/SP) | UserDefaults,键名保持一致 | 等价 |
| 10 | in-app 语言切换 LocaleHelper | .environment(\.locale) 手动覆盖,5 语言 | 等价 |

## Success Criteria

1. **文件覆盖**:87 个 Kotlin 源文件每个在 SPEC 附录映射表有一行归宿(移植/等价/平台跳过三类,跳过仅限表#3 相关)
2. **测试绿**:Android 全部测试用例的 iOS 版全绿,含 389×5 字符串 parity 测试
3. **真机验收**:`./scripts/build-ipa.sh` 产出 IPA → 用户 AltStore 装上 iOS 26 真机 → 课表三视图/编辑/导入(WakeUp文本+JSON+教务直连)/导出三格式/5 类 widget/每日+课前通知/5 主题/多课表,逐项与 Android 版对照可用
4. 真机 widget 数据与 app 同步(App Group 生效),课程编辑后 widget 刷新

## Open Questions

无阻塞项。风险预案:
- AltStore 免费账号对 app+widget extension 的 App Group 注入如真机验证失败 → 降级方案:widget ext 直读同一 GRDB 文件路径(无沙箱共享需 App Group,此路不通则改 AltStore PAL 或付费账号,届时再问)
- GRDB 经镜像拉取失败 → 退 raw SQLite3 C API 薄 DAO 层(再问)
```
