# Game Center 成就系统设计文档

**日期**: 2026-11-05  
**状态**: 已批准  
**作者**: AI Assistant

## 概述

为 Sleepy iOS v1.0.62+ 集成 Game Center 成就系统，8 个成就对应用户关键操作里程碑。成就完全由 Game Center 管理和展示，App 内无 UI，仅在后台触发解锁并由系统弹出通知。

## 成就列表

| 成就名称 | ID | 分值 | 触发条件 |
|---------|-----|------|---------|
| 组织，我来了 | `import_success` | 5 | 首次成功导入课表（任何教务系统） |
| 成为"先知" | `notification_on` | 5 | 开启课程提醒 |
| 永别了，主程序 | `widget_add_success` | 10 | 系统实际添加了桌面小组件 |
| 省时又省力 | `share_success` | 10 | 弹出分享弹窗 |
| 嗯，希望下次能用上 | `export_backup` | 15 | 导出备份文件 |
| 我熟练的可以给这个软件写一个新手引导 | `import_twice` | 15 | 累计成功导入 2 次 |
| 阅后即焚 | `delete_once` | 15 | 首次删除任意课表 |
| 老的新面孔还是新的老面孔 | `import_backup` | 20 | 成功导入备份文件 |

## 架构设计

### 核心模块

#### 1. GameCenterManager

**职责**：
- App 启动时自动认证 Game Center
- 上报成就解锁到 Game Center
- 处理认证失败（静默，不影响 App）

**接口**：
```swift
class GameCenterManager {
    static let shared = GameCenterManager()
    
    // App 启动时调用
    func authenticate()
    
    // 解锁成就
    func unlockAchievement(id: String, completion: ((Bool) -> Void)?)
    
    // 检查是否已认证
    var isAuthenticated: Bool { get }
}
```

#### 2. AchievementTracker

**职责**：
- 检查触发条件
- 查询本地解锁状态
- 协调 GameCenterManager 上报 + AppPrefs 本地标记

**接口**：
```swift
class AchievementTracker {
    static let shared = AchievementTracker()
    
    // 检查并触发成就
    func checkImportSuccess()
    func checkNotificationOn()
    func checkWidgetAdd()
    func checkShareSuccess()
    func checkExportBackup()
    func checkDeleteOnce()
    func checkImportBackup()
    
    // 内部：增加导入计数并检查 import_twice
    private func incrementImportCount()
}
```

#### 3. AppPrefs 扩展

**新增字段**：
```swift
// 成就解锁标记
private static let KEY_ACHIEVEMENT_IMPORT_SUCCESS = "achievement_import_success"
private static let KEY_ACHIEVEMENT_NOTIFICATION_ON = "achievement_notification_on"
private static let KEY_ACHIEVEMENT_WIDGET_ADD = "achievement_widget_add"
private static let KEY_ACHIEVEMENT_SHARE_SUCCESS = "achievement_share_success"
private static let KEY_ACHIEVEMENT_EXPORT_BACKUP = "achievement_export_backup"
private static let KEY_ACHIEVEMENT_IMPORT_TWICE = "achievement_import_twice"
private static let KEY_ACHIEVEMENT_DELETE_ONCE = "achievement_delete_once"
private static let KEY_ACHIEVEMENT_IMPORT_BACKUP = "achievement_import_backup"

// 导入计数
private static let KEY_ACHIEVEMENT_IMPORT_COUNT = "achievement_import_count"
```

### 数据流

```
1. App 启动
   └─> AppDelegate/SceneDelegate
       └─> GameCenterManager.shared.authenticate()

2. 业务操作触发
   └─> AchievementTracker.checkXXX()
       ├─> 检查本地标记（AppPrefs）
       ├─> 未解锁？
       │   ├─ 是：上报 GameCenter + 写本地标记
       │   └─ 否：跳过
       └─> Game Center 自动弹系统通知
```

## 集成点

### 1. 导入成功（3 个成就）

**位置**：`JwImportFlow` / 导入成功回调

**逻辑**：
```swift
// 导入成功后
AchievementTracker.shared.checkImportSuccess()  // 首次导入
// 内部会自动检查 import_twice
```

**备份导入**：
```swift
// WakeUP 分享码导入成功后
AchievementTracker.shared.checkImportBackup()
```

### 2. 开启提醒

**位置**：`ReminderSettingsScreen` / 提醒开关切换

**逻辑**：
```swift
// 提醒开关从 false → true
if newValue == true {
    AchievementTracker.shared.checkNotificationOn()
}
```

### 3. 添加 Widget

**位置**：App 进入前台时检测

**逻辑**：
```swift
// AppDelegate/SceneDelegate sceneWillEnterForeground
WidgetCenter.shared.getCurrentConfigurations { result in
    if case .success(let widgets) = result, !widgets.isEmpty {
        AchievementTracker.shared.checkWidgetAdd()
    }
}
```

### 4. 分享弹窗

**位置**：分享功能触发处（UIActivityViewController 或自定义弹窗）

**逻辑**：
```swift
// 弹窗显示时
AchievementTracker.shared.checkShareSuccess()
```

### 5. 导出备份

**位置**：导出操作完成处

**逻辑**：
```swift
// 导出文件成功保存后
AchievementTracker.shared.checkExportBackup()
```

### 6. 删除课表

**位置**：`TimeTableDao.delete()` 成功后

**逻辑**：
```swift
// Repository 层删除成功
AchievementTracker.shared.checkDeleteOnce()
```

## 错误处理

### Game Center 未登录
- `authenticate()` 静默失败
- `unlockAchievement()` 检查 `isAuthenticated`，未认证则跳过上报
- 本地标记仍然写入，避免重复触发

### 网络错误
- 上报失败不影响本地标记
- 下次启动重新认证后，已标记的成就不会重复上报

### 成就 ID 不匹配
- GameKit 返回错误时记录日志
- 不崩溃，不阻塞业务流程

## 开发与测试

### DEBUG 功能

```swift
#if DEBUG
extension AchievementTracker {
    // 重置所有成就（仅开发用）
    func resetAllAchievements() {
        // 清除本地标记
        // 重置 Game Center 进度（需要删除沙盒数据）
    }
}
#endif
```

### 测试策略

1. **沙盒环境测试**：
   - 使用 Game Center 沙盒账号
   - 逐个触发 8 个成就
   - 验证系统通知弹出

2. **本地状态验证**：
   - 检查 AppPrefs 标记正确写入
   - 重复触发不重复上报

3. **边界情况**：
   - 未登录 Game Center → 正常使用 App
   - 网络断开 → 本地标记仍生效
   - 累计成就（import_twice）计数准确

## 文件结构

```
Sleepy/
├── gamecenter/
│   ├── GameCenterManager.swift       // 认证和上报
│   └── AchievementTracker.swift      // 触发逻辑
├── data/
│   └── AppPrefs.swift                // 扩展：本地标记
└── ui/
    └── [各触发点集成]
```

## 实现顺序

1. 创建 `GameCenterManager` - 认证和上报基础
2. 扩展 `AppPrefs` - 本地存储
3. 创建 `AchievementTracker` - 触发逻辑
4. 在 App 启动处集成认证
5. 在 8 个触发点集成调用
6. 测试验证

## 注意事项

- **隐私**：Game Center 是可选功能，用户可以选择不登录
- **性能**：认证和上报都是异步操作，不阻塞主线程
- **兼容性**：仅 iOS 14+ 支持 GameKit 现代 API
- **App Store 配置**：8 个成就需在 App Store Connect 中预先配置，ID 必须完全匹配
