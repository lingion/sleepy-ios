<p align="center">
  <img src="docs/logo.png" width="120">
</p>

<h1 align="center">Sleepy · 课程表 iOS</h1>

<p align="center">
  Sleepy 课程表的 iOS 移植版，基于 SwiftUI + GRDB + WidgetKit。<br>
  与 Android 版功能对齐，版本号 a.v.1.0.34
</p>

<p align="center">
  <a href="https://github.com/lingion/sleepy-ios/releases"><img src="https://img.shields.io/github/v/release/lingion/sleepy-ios?style=flat-square&label=version" alt="Latest Release"></a>
  <img src="https://img.shields.io/github/stars/lingion/sleepy-ios?style=flat-square&logo=github" alt="Stars">
  <img src="https://img.shields.io/badge/platform-iOS-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/lang-Swift-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/minSDK-16.0-blue?style=flat-square" alt="Min SDK">
</p>

<p align="center">
  <a href="https://github.com/lingion/sleepy-ios/releases">⬇ 下载 IPA</a>
</p>

---

> **Keywords (SEO):** iOS schedule app, 课程表, 课表, timetable, university schedule, SwiftUI, WidgetKit, iOS widget, home screen widget, 开源课表, 开源课程表

---

## 截图一览

<p align="center">
  <img src="docs/screenshots/01-schedule-week.png" width="30%">
  <img src="docs/screenshots/02-schedule-grid.png" width="30%">
  <img src="docs/screenshots/03-today.png" width="30%">
</p>
<p align="center">
  <img src="docs/screenshots/widget-today.png" width="22%">
  <img src="docs/screenshots/widget-twoday.png" width="22%">
  <img src="docs/screenshots/widget-weeklist.png" width="22%">
  <img src="docs/screenshots/widget-weekgrid.png" width="22%">
</p>

<p align="center">
  <code>a.v1.0.34</code> · iOS 16.0+ · 包名 <code>com.lingion.sleepy</code>
</p>

---

## 概要

| 项 | 值 |
|---|---|
| 包名 | `com.lingion.sleepy` |
| 最低 SDK | `16.0` |
| 架构 | arm64 |
| 语言 | zh-CN · en |

iOS 版课程表工具。主旨：**轻、快、准**。零壳依赖，支持手动添加、多格式解析、五类桌面 Widget、深色模式，与 Android 版功能对齐。

---

## 📅 三视图

课表主页内置三种视图，顶部 SegmentedControl 一键切换。

| 视图 | 说明 |
|---|---|
| **周视图**（7 日横排 × N 节） | 横向时间轴，展示整周课程 |
| **网格视图**（时间网格 · 课程色块） | 经典课程表布局 |
| **今日视图**（底部"今日"Tab · 当日课程） | 只看今天有哪些课 |

特性：
- 左/右滑周切换器，实时算周次
- 课程按"起止周+单双周+起止节"自动过滤当前周
- 点击课程卡片弹出详情底部弹窗

---

## 📚 多课表管理

可同时管理多张独立课表，每张表拥有自己的节次时间表、开学日期、最大周数。

新建/编辑课表必填项：名称、开始日期、最大周数、节次时间表。

---

## ⏰ 节次配置

手动模式逐节设置起止时间。

---

## ➕ 手动添加课程

入口在底栏「课表管理」→「添加课程」。

字段：课名 · 教师 · 教室 · 备注 · 星期 · 起止节 · 起止周 · 单双周类型 · 课程色。

---

## 📤 导出课表

支持导出为 JSON 格式，可被 Android 版 Sleepy 导入。

---

## 🧩 桌面 Widget（5 类）

五类 Widget，通过 WidgetKit 实现，App Group 数据共享。

| Widget | 尺寸 | 用途 |
|---|---|---|
| **Today** | 小 | 今日课程列表 |
| **TwoDay** | 中 | 今天 + 明天 |
| **WeekList** | 中 | 7 日课程统计 + 名称 |
| **WeekGrid** | 大 | 完整时间网格 + 课程块 |
| **WeekView** | 大 | 周视图 |

实现要点：
- 纯 WidgetKit 实现，无 Glance
- App Group：`group.com.lingion.sleepy.ios`
- 配色与 app 主题实时同步（深色模式）
- 课程色按黄金角 (137.508°) HSL 分布

---

## 🌙 深色模式

跟随系统自动切换深色/浅色主题。

---

## 技术栈

```
language        = Swift 5.9
ui              = SwiftUI
storage         = GRDB 6.29.3
widgets         = WidgetKit
navigation      = SwiftUI NavigationStack
prefs           = AppPrefs (UserDefaults)
serialization   = Codable
build           = XcodeGen 14.3.1
xcode           = 14.3.1
```

---

## 项目结构

```
Sleepy/
├── Sleepy/
│   ├── SleepyApp.swift              # App 入口
│   ├── data/
│   │   └── AppDatabase.swift        # GRDB 数据库
│   ├── ui/
│   │   ├── component/               # CourseTableView / PillNavigationBar /
│   │   │                           # SegmentedSwitcher / CourseOverlayCard
│   │   ├── screen/
│   │   │   ├── schedule/            # 周视图 + 网格视图 + 今日视图
│   │   │   ├── edit/               # 课程编辑
│   │   │   └── mine/               # 我的 / 关于
│   │   └── theme/                  # Theme + ThemePresets
│   ├── util/                        # AppPrefs / DateUtils / LocaleHelper
│   └── widget/                     # Widget 视图
├── SleepyWidget/                    # Widget Extension
├── SleepyTests/                     # 单元测试
├── SleepyUITests/                   # UI 测试
├── scripts/                         # 构建脚本
├── project.yml                     # XcodeGen 配置
└── README.md
```

---

## 构建 & 安装

### 前置

```bash
# 安装 XcodeGen
brew install xcodegen

# 或使用国内镜像
brew install xcodegen --registry=https://registry.npmmirror.com
```

### 编译

```bash
git clone https://github.com/lingion/sleepy-ios.git
cd sleepy-ios

# 生成 Xcode 项目
xcodegen generate

# Debug 构建
xcodebuild -project Sleepy.xcodeproj \
  -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  build
```

### 测试

```bash
# 单元测试
xcodebuild -project Sleepy.xcodeproj \
  -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  test

# UI 测试
xcodebuild -project Sleepy.xcodeproj \
  -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  -only-testing:SleepyUITests \
  test
```

### 安装

下载 Release 中的 IPA 文件，使用 AltStore 或 SideStore 签名安装。

---

## Android 原版

https://github.com/lingion/sleepy

---

## License

[GPL-3.0](LICENSE)