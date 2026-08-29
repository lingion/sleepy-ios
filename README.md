<h1 align="center">Sleepy · 课程表 iOS</h1>

<h1 align="center">Sleepy · 课程表 iOS</h1>

<p align="center">
  Sleepy 课程表的 iOS 移植版，基于 SwiftUI + GRDB + WidgetKit。<br>
  与 Android 版功能对齐；工程版本 1.0.34，最新发布 a.v.1.0.41
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
  <img src="audit_shots/A1_schedule_zh-Hans_light.png" width="30%">
  <img src="audit_shots/A1_today_zh-Hans_light.png" width="30%">
  <img src="audit_shots/A1_manage_zh-Hans_light.png" width="30%">
</p>

<p align="center">
  <code>a.v.1.0.41</code> · iOS 16.0+ · 包名 <code>com.lingion.sleepy</code>
</p>

---

## 概要

| 项 | 值 |
|---|---|
| 包名 | `com.lingion.sleepy` |
| 最低 SDK | `16.0` |
| 架构 | arm64 |
| 语言 | zh-Hans · zh-Hant · en · ja · es |

iOS 版课程表工具。主旨：**轻、快、准**。零壳依赖，支持手动添加、多格式解析、五类桌面 Widget、深色模式，与 Android 版功能对齐。

---

## 📅 课表视图

课表页提供两种布局，顶部 SegmentedSwitcher 切换；今日课程在底部「今日」标签页。

| 视图 | 说明 |
|---|---|
| **周视图**（7 日横排 × N 节） | 横向时间轴，展示整周课程 |
| **网格视图**（时间网格 · 课程色块） | 经典课程表布局 |
| **今日**（底部 Tab） | 只看今天有哪些课 |

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

入口在底栏「我的」→「导出课表」。三种格式：

| 格式 | 用途 |
|---|---|
| WakeUp JSON | 供 Android 版 Sleepy 导入 |
| 分享文本 | 直接分享课表内容 |
| ICS | 导入日历应用 |

---

## 🧩 桌面 Widget（5 类）

五类 Widget，通过 WidgetKit 实现，App Group 数据共享。

| Widget | 支持尺寸 | 用途 |
|---|---|---|
| **Today** | 小、中、大 | 今日课程列表 |
| **TwoDay** | 中、大 | 今天 + 明天 |
| **WeekList** | 中、大 | 7 日课程统计 + 名称 |
| **WeekGrid** | 中、大 | 完整时间网格 + 课程块 |
| **WeekView** | 中、大 | 周视图 |

实现要点：
- 纯 WidgetKit 实现，无 Glance
- App Group：`group.com.lingion.sleepy.ios`
- 配色与 app 主题实时同步（深色模式）
- 课程色按黄金角 (137.508°) HSL 分布

---

## 🌙 深色模式

浅色 / 深色 / 跟随系统三种模式（「我的」→「外观」），默认跟随系统。

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
│   ├── SleepyApp.swift              # App 入口（Tab 壳 + overlay 导航 + 深链）
│   ├── data/                        # GRDB 数据库、实体、解析器、仓储
│   ├── theme/                       # Theme + ThemePresets
│   ├── ui/
│   │   ├── component/               # CourseTableView / PillNavigationBar / SegmentedSwitcher
│   │   └── screen/
│   │       ├── schedule/            # 周视图 + 网格视图
│   │       ├── today/               # 今日课程
│   │       ├── imports/             # 课表导入（含教务解析）
│   │       ├── edit/                # 课程编辑
│   │       ├── manage/              # 课表管理
│   │       └── mine/                # 我的 / 外观 / 导出 / 关于
│   ├── resources/                   # 多语言 Localizable.strings + schools.json
│   ├── util/                        # AppPrefs / DateUtils
│   └── widget/                      # Widget 视图
├── SleepyWidget/                    # Widget Extension
├── SleepyTests/                     # 单元测试
├── SleepyUITests/                   # UI 测试
├── scripts/                         # 构建/测试脚本
├── project.yml                      # XcodeGen 配置
└── README.md
```

---

## 构建 & 安装

### 前置

安装 XcodeGen，并确保 Xcode 14.3 或更高版本：

```bash
brew install xcodegen
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

[GPL-3.0](LICENSE)（LICENSE 文件待补充）