# sleepy-iOS Android 特定功能审计报告

## 审计日期
2026-11-03（本文是审计时点快照，「待修复/待移除」多数已在 180fbfb 等提交落地，以当前代码为准）

## 审计背景
App Store 审核反馈指出项目中存在多个 Android 特定功能：
- 部分功能在 iOS 已有原生替代但未正确对接
- 部分功能"有开关无实现"（空壳功能）
- 部分功能完全不适用于 iOS 平台

## 审计方法
1. 对比 Android (`/Users/kerrylee/sleepy`) 与 iOS (`/Users/kerrylee/sleepy-iOS`) 源码
2. 扫描 AppPrefs.kt (81 个设置项) vs AppPrefs.swift (147 个方法)
3. 逐个分析设置屏幕中的功能实现

---

## 一、已确认的 Android 特定功能

### 1. ⚠️ **高刷新率开关** (Android 专有)
- **Android**: `KEY_HIGH_REFRESH` - 钉屏幕最高刷率 vs 系统省电调度
- **iOS 现状**: 无对应功能
- **原因**: iOS ProMotion 完全由系统自动调度，无公开 API
- **处理**: ✅ **已在代码注释中标注** (`GeneralSettingsScreen.swift:218`)
- **文档**: `PlatformParityNotes.swift` 已记录
- **修复**: 无需修复，正常差异

### 2. ⚠️ **液态玻璃底栏主题** (Android 专有)
- **Android**: `KEY_DOCK_THEME` = "classic" / "liquid_glass"
- **iOS 现状**: 只有 classic / floating 两档
- **原因**: Material You 液态玻璃效果是 Android 专有视觉语言
- **处理**: 需要**隐藏或移除**相关 UI
- **修复状态**: ❌ **待修复**

### 3. ⚠️ **vivo 原子组件/流体卡片** (Android 专有)
- **Android**: `KEY_BEFORE_CLASS_FLUID` - vivo 原子组件实时流体卡片
- **iOS 现状**: 平台有对应物(ActivityKit 实况活动/灵动岛, iOS 16.1+), 本 app 未实现该切片
- **原因**: vivo OriginOS 专属 API; UI 移除依据是审核合规(他平台厂商文案误导 iOS 用户)
- **处理**: 需要**完全移除**相关 UI
- **修复状态**: ❌ **待修复**

### 4. ⚠️ **Android 13+ 动态图标** (Android 专有)
- **Android**: Themed Icons API (Android 13+)
- **iOS 现状**: 无对应功能
- **原因**: iOS 只有静态图标 + App Icon Sets
- **处理**: 需要**移除**相关设置
- **修复状态**: ❌ **待修复**

### 5. ⚠️ **通知渠道管理** (Android 专有)
- **Android**: NotificationChannel 精细化管理（课前提醒/每日摘要/上课勿扰等多个渠道）
- **iOS 现状**: 统一 UNNotificationCategory，无"渠道"概念
- **原因**: iOS 通知权限是应用级，不支持渠道级管理
- **处理**: 需要**用 iOS 原生统一设置替代**
- **修复状态**: ❌ **待修复**

---

## 二、有开关无实现的功能（需核查）

### 1. ❓ **撤回深度设置** (可能空壳)
- **Android**: `KEY_UNDO_DEPTH` - 多步撤回深度（-1无限/0禁用/N保留N步，默认5）
- **iOS 现状**: 需要检查是否有实现
- **检查点**: `settings_undo_depth` 在 iOS 中是否存在？
- **修复状态**: 🔍 **待检查**

### 2. ❓ **Material Icons 支持**
- **Android**: 使用 Material Symbols 图标系统
- **iOS 现状**: 应该使用 SF Symbols 替代
- **检查点**: 代码中是否仍引用 Material Icons？
- **修复状态**: 🔍 **待检查**

---

## 三、需要 iOS 原生替代的功能

### 1. 🔄 **通知权限与设置**
#### Android 实现
- 多个 NotificationChannel：
  - `CHANNEL_BEFORE_CLASS` - 课前提醒
  - `CHANNEL_DAILY_SUMMARY` - 每日摘要
  - `CHANNEL_CLASS_DND` - 上课勿扰
  - `CHANNEL_VENDOR_LIVE` - vivo 流体卡片
- 每个渠道可独立开关、设置优先级

#### iOS 应有的实现
- 统一 UNNotificationCategory
- 用户通过系统设置 → Sleepy → 通知 统一管理
- App 内只需：
  - 主开关：允许/禁止所有通知
  - 功能开关：每日摘要、课前提醒、自动勿扰（对应 category）

#### 修复计划
- [ ] 移除 Android 渠道管理 UI
- [ ] 添加"跳转系统通知设置"按钮
- [ ] 保留功能开关（对应 category）

### 2. 🔄 **电池优化豁免**
#### Android 实现
- 引导用户关闭 Doze 模式限制
- REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 权限

#### iOS 应有的实现
- iOS 无需此功能（后台限制由系统统一管理）
- Background Modes 正确配置即可

#### 修复计划
- [ ] 移除电池优化相关 UI
- [ ] 确保 Background Modes 配置正确

### 3. 🔄 **Material Dynamic Colors**
#### Android 实现
- Android 12+ Material You 动态取色
- `dynamicLightColorScheme()` / `dynamicDarkColorScheme()`

#### iOS 应有的实现
- iOS 17+ Adaptive Color API
- 或使用 Asset Catalog 的 Color Set + Dynamic Color

#### 修复计划
- [ ] 检查是否正确使用 iOS Dynamic Colors
- [ ] 移除 Material You 相关文案

---

## 四、设置项对比清单

### 通用设置 (GeneralSettingsScreen)

| 设置项 | Android | iOS | 状态 | 备注 |
|--------|---------|-----|------|------|
| 课程时间显示（节次/时间） | ✅ | ✅ | ✅ 对齐 | |
| 网格卡片副信息 | ✅ | ✅ | ✅ 对齐 | |
| 显示星期 | ✅ | ✅ | ✅ 对齐 | |
| 课程胶囊统一底色 | ✅ | ✅ | ✅ 对齐 | |
| 节假日设置 | ✅ | ✅ | ✅ 对齐 | |
| **高刷新率** | ✅ | ❌ | ✅ 正常差异 | iOS 无此概念 |
| 启动默认页 | ✅ | ✅ | ✅ 对齐 | |
| 底栏样式（贴底/悬浮） | ✅ | ✅ | ✅ 对齐 | |
| **液态玻璃主题** | ✅ | ❌ | ⚠️ 待移除 | Android 专有 |
| 语言设置 | ✅ | ✅ | ✅ 对齐 | |
| **撤回深度** | ✅ | ❓ | 🔍 待检查 | 需验证实现 |
| 数据迁移 | ✅ | ✅ | ✅ 对齐 | |

### 小组件设置

| 设置项 | Android | iOS | 状态 | 备注 |
|--------|---------|-----|------|------|
| 小组件统一底色 | ✅ | ✅ | ✅ 对齐 | |
| 小组件分隔线 | ✅ | ✅ | ✅ 对齐 | |
| 最近有课日 | ✅ | ✅ | ✅ 对齐 | |
| 竖排标点优化 | ✅ | ✅ | ✅ 对齐 | |
| 管理桌面小组件 | ✅ | ✅ | ✅ 对齐 | |

### 实验室功能

| 设置项 | Android | iOS | 状态 | 备注 |
|--------|---------|-----|------|------|
| 自适应行高 | ✅ | ✅ | ✅ 对齐 | |
| 双指捏放 | ✅ | ✅ | ✅ 对齐 | |
| 自动收起空白晚间 | ✅ | ✅ | ✅ 对齐 | |
| 网格分隔线 | ✅ | ✅ | ✅ 对齐 | |
| 长课间留白 | ✅ | ✅ | ✅ 对齐 | |

### 提醒与通知 (ReminderScreen)

| 设置项 | Android | iOS | 状态 | 备注 |
|--------|---------|-----|------|------|
| 主开关 | ✅ | ✅ | ✅ 对齐 | |
| 每日摘要 | ✅ | ✅ | ✅ 对齐 | |
| 明日课表 | ✅ | ✅ | ✅ 对齐 | |
| 课前提醒 | ✅ | ✅ | ✅ 对齐 | |
| 上课自动勿扰 | ✅ | ✅ | ✅ 对齐 | |
| **通知渠道管理** | ✅ | ❌ | ⚠️ 待替代 | 用 iOS 系统设置 |
| **电池优化豁免** | ✅ | ❌ | ⚠️ 待移除 | iOS 不需要 |
| **vivo 流体卡片** | ✅ | ❌ | ⚠️ 已移除 | vivo 专有；iOS 有对应物 = ActivityKit 实况活动/灵动岛，本 app 未实现，移除 UI 为审核合规 |

### 外观与主题 (AppearanceScreen)

| 设置项 | Android | iOS | 状态 | 备注 |
|--------|---------|-----|------|------|
| 亮/暗/跟随系统 | ✅ | ✅ | ✅ 对齐 | |
| 主题色 | ✅ | ✅ | ✅ 对齐 | |
| **Material Dynamic Colors** | ✅ | ❌ | ⚠️ 待替代 | 用 iOS Dynamic Colors |
| **Android 13+ 动态图标** | ✅ | ❌ | ⚠️ 待移除 | iOS 不支持 |
| 课程配色模式 | ✅ | ✅ | ✅ 对齐 | |
| 网格/周视图缩放 | ✅ | ✅ | ✅ 对齐 | |
| 圆角比例 | ✅ | ✅ | ✅ 对齐 | |

---

## 五、修复优先级

### P0 - 必须修复（影响审核）
1. ⚠️ **移除 vivo 流体卡片相关 UI** - Android 厂商专有
2. ⚠️ **移除液态玻璃底栏主题选项** - Android 专有视觉语言
3. ⚠️ **移除 Android 13+ 动态图标设置** - iOS 不支持
4. ⚠️ **移除通知渠道管理** - 用 iOS 系统设置替代
5. ⚠️ **移除电池优化豁免** - iOS 不需要

### P1 - 应该修复（影响体验）
1. 🔍 **检查撤回深度功能** - 确认是否空壳
2. 🔄 **用 SF Symbols 替换 Material Icons** - 如果存在引用
3. 🔄 **用 iOS Dynamic Colors 替换 Material You** - 如果存在文案

### P2 - 可选优化
1. 统一 iOS 与 Android 文案差异
2. 补充平台差异文档

---

## 六、修复实施计划

### 阶段一：审计与定位（当前阶段）
- [x] 生成此审计报告
- [ ] 逐个检查上述 P0/P1 功能在代码中的位置

### 阶段二：P0 修复
每个功能一个 commit：
1. 移除 vivo 相关代码
2. 移除液态玻璃主题
3. 移除动态图标设置
4. 重构通知设置页面
5. 移除电池优化相关

### 阶段三：P1 修复
1. 检查并修复撤回深度
2. 检查并替换图标系统
3. 检查并替换动态颜色

### 阶段四：验证与文档
1. 全量回归测试
2. 更新 PlatformParityNotes.swift
3. 提交 App Store Review

---

## 七、检查清单

### 需要搜索的代码特征
```bash
# vivo 相关
grep -r "vivo\|fluid\|atomic" --include="*.swift"

# 通知渠道
grep -r "channel\|NotificationChannel" --include="*.swift"

# Material
grep -r "Material\|material" --include="*.swift"

# 液态玻璃
grep -r "liquid\|glass" --include="*.swift"

# 电池优化
grep -r "battery\|optimization" --include="*.swift"

# 撤回深度
grep -r "undo.*depth\|KEY_UNDO" --include="*.swift"
```

---

## 附录：参考文档

### iOS 平台差异说明
- 文件位置：`PlatformParityNotes.swift`
- 已记录：高刷新率 API 差异

### Android 源码参考
- `AppPrefs.kt`: 81 个配置项
- `GeneralSettingsScreen.kt`: 通用设置
- `ReminderScreen.kt`: 通知提醒设置
- `AppearanceScreen.kt`: 外观主题设置

### iOS 源码位置
- `AppPrefs.swift`: 147 个方法（包含 getter/setter）
- `GeneralSettingsScreen.swift`: 通用设置（已对齐 Android v1.0.61）
- `ReminderScreen.swift`: 通知提醒设置
- `AppearanceScreen.swift`: 外观主题设置

