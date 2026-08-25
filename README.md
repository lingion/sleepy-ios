# Sleepy 课程表 iOS

Sleepy 课程表的 iOS 移植版，基于 SwiftUI、GRDB、WidgetKit 开发。

## 功能

- 📅 课程表管理：导入、手动添加、编辑、删除
- 📱 Widget：今日、两天、周视图、课程列表
- 🌙 深色/浅色主题跟随系统
- 🔄 数据持久化：GRDB (SQLite)
- 📤 导出/导入：JSON 格式

## 技术栈

- SwiftUI
- GRDB 6.29.3
- WidgetKit
- iOS 16.0+
- Xcode 14.3.1
- XcodeGen

## 构建

```bash
# 安装依赖
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 构建 Debug 版本
xcodebuild -project Sleepy.xcodeproj \
  -scheme Sleepy \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  build
```

## 测试

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

## 安装

### AltStore（推荐）

1. 下载 Release 中的 `.ipa` 文件
2. 使用 AltStore 签名安装
3. 或使用 SideStore 自签

### 手动构建

```bash
# 构建 IPA（需配置签名证书）
./scripts/build-ipa.sh
```

## App Group

- `group.com.lingion.sleepy.ios` - 用于 App 与 Widget 数据共享

## 项目结构

```
Sleepy/               # 主 App 源码
  ├── ui/             # 界面层
  ├── data/           # 数据层 (GRDB)
  ├── widget/         # Widget 扩展
  └── ...
SleepyWidget/         # Widget Extension
SleepyTests/          # 单元测试
SleepyUITests/       # UI 测试
scripts/              # 构建脚本
project.yml           # XcodeGen 配置
```

## Android 原版

https://github.com/lingion/sleepy
