# Android 特定功能修复计划

## 审计结果总结

经过代码审计，发现以下 Android 特定功能需要修复：

### ✅ 已正确处理
1. **高刷新率** - 已在 PlatformParityNotes.swift 中标注为 iOS 不支持
2. **液态玻璃底栏** - iOS 代码中未找到引用，Android 专有
3. **动态图标** - iOS 代码中未找到引用，Android 专有
4. **通知渠道** - 已在注释中标注 iOS 无此概念

### ❌ 需要修复的功能
1. **vivo 流体卡片 (Fluid Card)** - 存在完整 UI 和设置，需要移除
2. **电池优化豁免** - 存在 UI 引导，需要移除

### 🔍 需要进一步检查
1. **撤回深度 (Undo Depth)** - Android 有设置，iOS 未找到对应实现

---

## 修复任务清单

### 任务 1: 移除 vivo 流体卡片功能

#### 影响范围
- **文件**: `Sleepy/ui/screen/mine/ReminderScreen.swift`
- **行号**: 59-60, 72, 111, 114, 394-450, 560-567
- **AppPrefs 方法**:
  - `isBeforeClassFluidEnabled()` / `setBeforeClassFluidEnabled()`
  - `getBeforeClassFluidPrimary()` / `setBeforeClassFluidPrimary()`

#### 具体修改
1. **ReminderScreen.swift**:
   - 删除 `@State private var fluidEnabled` (line 59)
   - 删除 `@State private var fluidPrimary` (line 60)
   - 删除 `.onChange(of: fluidEnabled)` (line 114)
   - 删除整个 "流体卡片" 设置块 (lines 394-450)
   - 删除 `fluidPrimaryLabel` computed property (lines 561-567)

2. **AppPrefs.swift**:
   - 标记 fluid 相关方法为 `@available(*, deprecated, message: "vivo 流体卡片功能已移除(App Store 合规)；iOS 对应物为 ActivityKit 实况活动/灵动岛，本 app 未实现")`
   - 或直接删除（如果没有其他引用）

3. **本地化文件**:
   - 保留 key 但标注为 Android only（防止构建错误）

#### 提交信息
```
fix(reminder): 移除 vivo 流体卡片功能

vivo 流体卡片是 vivo OriginOS 专有的原子组件 API（iOS 对应物为 ActivityKit
实况活动/灵动岛，本 app 未实现该切片）。移除相关 UI 和设置项的原因是
App Store 审核合规：描述其他平台厂商功能的 UI 文案会误导 iOS 用户。

- 删除 ReminderScreen 中 fluid 相关状态和 UI
- 标记 AppPrefs 中 fluid 相关方法为过期
- 影响: 提醒设置页少一个"实验性"功能项

相关 issue: App Store 审核反馈 Android 特定功能
```

---

### 任务 2: 移除电池优化豁免引导

#### 影响范围
- **文件**: `Sleepy/ui/screen/mine/ReminderScreen.swift`
- **搜索关键词**: `battery`, `optimization`, `BatteryOptimizationIntents`

#### 具体位置
查找代码中是否有：
- "电池优化" / "Battery Optimization" 相关文案
- 跳转到系统设置的按钮
- `BatteryOptimizationIntents.swift` 文件

#### 修改步骤
1. 搜索所有 battery 相关代码
2. 删除引导用户关闭电池优化的 UI
3. 删除或标注 `BatteryOptimizationIntents.swift`

#### 提交信息
```
fix(reminder): 移除电池优化豁免引导

iOS 后台限制由系统统一管理，无需（也无法）
单独申请电池优化豁免。移除相关引导 UI。

相关 issue: App Store 审核反馈 Android 特定功能
```

---

### 任务 3: 检查撤回深度功能实现

#### 检查步骤
1. 搜索 `undo` 相关代码：
   ```bash
   grep -r "undo\|Undo\|UNDO" --include="*.swift" .
   ```

2. 查看 Android 实现：
   - `KEY_UNDO_DEPTH` 在 `AppPrefs.kt` 中的用法
   - `GeneralSettingsScreen.kt` 中的 UI

3. 确认 iOS 状态：
   - 是否有 `getUndoDepth()` / `setUndoDepth()` 方法？
   - 是否有对应的 UI？
   - 是否有实际的撤回/重做功能？

#### 三种可能结果

**情况 A**: iOS 未实现
- 无需修复（功能本身就不存在）

**情况 B**: iOS 有功能但无设置 UI
- 添加设置 UI 以匹配 Android

**情况 C**: iOS 有设置 UI 但功能空壳
- 删除设置 UI
- 标记相关 AppPrefs 方法为过期

#### 提交信息（如需删除）
```
fix(settings): 移除未实现的撤回深度设置

iOS 版本未实现多步撤回功能，但保留了设置 UI，
导致"有开关无功能"。删除空壳设置项。

相关 issue: App Store 审核反馈空壳功能
```

---

### 任务 4: 检查 Material Icons 引用

#### 检查步骤
```bash
cd /Users/kerrylee/sleepy-iOS
grep -r "Material\|material" --include="*.swift" . | grep -i icon
```

#### 预期结果
- iOS 应使用 `Image(systemName:)` (SF Symbols)
- 不应有 Material Icons 的引用

#### 如果发现引用
1. 替换为对应的 SF Symbols
2. 查阅 [SF Symbols App](https://developer.apple.com/sf-symbols/) 找对应图标

---

### 任务 5: 更新平台差异文档

#### 文件位置
`PlatformParityNotes.swift` 或 `docs/platform-differences.md`

#### 添加内容
```markdown
## 厂商专有/本 app 未实现的 Android 功能

### vivo 流体卡片 (Fluid Card)
- **Android**: vivo OriginOS 原子组件，课前提醒实时流体卡片
- **iOS**: 平台对应物 = ActivityKit 实况活动/灵动岛（iOS 16.1+），本 app 未实现该切片；移除 UI 是审核合规（他平台厂商文案误导 iOS 用户）
- **状态**: 主 App UI 已移除 (v1.x.x)

### 电池优化豁免
- **Android**: 引导用户关闭 Doze 模式限制
- **iOS**: 后台限制由系统统一管理，无需也无法单独申请
- **状态**: 已移除相关 UI (v1.x.x)

### 通知渠道管理
- **Android**: NotificationChannel 精细化管理（课前/每日/勿扰等多渠道）
- **iOS**: UNNotificationCategory，应用级权限，用户通过系统设置管理
- **实现**: iOS 用功能开关 + 系统设置跳转替代渠道管理
```

---

## 实施顺序

### 第一批（P0 - 立即修复）
1. ✅ 移除 vivo 流体卡片功能
2. ✅ 移除电池优化豁免引导

### 第二批（P1 - 审核前修复）
3. 🔍 检查并处理撤回深度功能
4. 🔍 检查 Material Icons 引用

### 第三批（P2 - 可选）
5. 📝 更新平台差异文档
6. 🧪 全量回归测试

---

## 验证清单

### 功能验证
- [ ] 提醒设置页面正常显示
- [ ] 所有开关都有对应功能
- [ ] 无 Android 特定文案
- [ ] 无空壳设置项

### 代码清理
- [ ] 无 `vivo` / `fluid` 关键词（除注释）
- [ ] 无 `battery optimization` 相关代码
- [ ] 无过期 AppPrefs 方法的活跃调用

### 文档更新
- [ ] PlatformParityNotes.swift 已更新
- [ ] CHANGELOG 已记录移除的功能

---

## 预计影响

### 用户可见变化
- 提醒设置页面少一个"流体卡片"实验性功能
- 提醒可靠性检查区不再有电池优化引导

### 开发者注意
- 合并后需要通知团队：这些功能已移除
- Android 版本保持不变

### 审核影响
- **正面**: 移除 Android 特定功能，通过审核概率提升
- **风险**: 无，这些功能 iOS 本就无法实现

---

## 相关文件索引

### 核心文件
- `Sleepy/ui/screen/mine/ReminderScreen.swift` - 提醒设置页
- `Sleepy/ui/screen/mine/GeneralSettingsScreen.swift` - 通用设置页
- `Sleepy/util/AppPrefs.swift` - 偏好设置存储
- `Sleepy/widget/notification/*` - 通知相关实现

### 参考文件
- `PlatformParityNotes.swift` - 平台差异说明
- `ANDROID_FEATURE_AUDIT.md` - 审计报告
- Android 源码: `/Users/kerrylee/sleepy/`

---

## 回滚方案

如果修复后出现问题：

```bash
# 回滚单个 commit
git revert <commit-hash>

# 或重新添加功能（标注为 Android only）
# 保留代码但在 UI 上隐藏
#if DEBUG
    // vivo 流体卡片 - 仅开发环境可见
    fluidCard()
#endif
```
