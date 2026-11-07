# Game Center 成就系统实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 集成 Game Center 成就系统，8 个成就对应用户关键操作，纯后台触发无 UI

**Architecture:** 单例 GameCenterManager 管理认证和上报，AchievementTracker 协调触发逻辑和本地标记，AppPrefs 持久化解锁状态

**Tech Stack:** GameKit, UserDefaults, Swift Concurrency

## Global Constraints

- iOS 14.0+ required for GameKit modern APIs
- 成就 ID 必须与 App Store Connect 配置完全一致
- Game Center 失败静默处理，不影响 App 功能
- 所有网络操作异步执行，不阻塞主线程
- 本地标记使用 AppPrefs 统一管理，与现有偏好设置一致

---

## 文件结构

**新增文件**：
- `Sleepy/gamecenter/GameCenterManager.swift` - Game Center 认证和成就上报
- `Sleepy/gamecenter/AchievementTracker.swift` - 成就触发逻辑和本地状态管理

**修改文件**：
- `Sleepy/data/AppPrefs.swift` - 扩展成就本地标记字段
- `Sleepy/SleepyApp.swift` - App 启动时初始化 Game Center
- `Sleepy/data/jw/JwImportFlow.swift` - 导入成功触发成就
- `Sleepy/ui/screen/mine/ReminderSettingsScreen.swift` - 提醒开关触发成就
- `Sleepy/ui/screen/mine/AllTablesScreen.swift` - 删除课表触发成就
- 分享功能触发点（待定位）
- 导出备份触发点（待定位）
- Widget 检测逻辑（待定位）

---

### Task 1: 扩展 AppPrefs 成就标记

**Files:**
- Modify: `Sleepy/data/AppPrefs.swift`

**Interfaces:**
- Produces: 9 个成就相关 getter/setter
  - `isAchievementImportSuccessUnlocked() -> Bool`
  - `setAchievementImportSuccessUnlocked(_ unlocked: Bool)`
  - `isAchievementNotificationOnUnlocked() -> Bool`
  - `setAchievementNotificationOnUnlocked(_ unlocked: Bool)`
  - `isAchievementWidgetAddUnlocked() -> Bool`
  - `setAchievementWidgetAddUnlocked(_ unlocked: Bool)`
  - `isAchievementShareSuccessUnlocked() -> Bool`
  - `setAchievementShareSuccessUnlocked(_ unlocked: Bool)`
  - `isAchievementExportBackupUnlocked() -> Bool`
  - `setAchievementExportBackupUnlocked(_ unlocked: Bool)`
  - `isAchievementImportTwiceUnlocked() -> Bool`
  - `setAchievementImportTwiceUnlocked(_ unlocked: Bool)`
  - `isAchievementDeleteOnceUnlocked() -> Bool`
  - `setAchievementDeleteOnceUnlocked(_ unlocked: Bool)`
  - `isAchievementImportBackupUnlocked() -> Bool`
  - `setAchievementImportBackupUnlocked(_ unlocked: Bool)`
  - `getAchievementImportCount() -> Int`
  - `incrementAchievementImportCount() -> Int` (返回新计数)

- [ ] **Step 1: 添加私有 key 常量**

在 `AppPrefs` 类中已有的私有 key 常量区域添加：

```swift
// ---- Game Center 成就标记 ----
private static let KEY_ACHIEVEMENT_IMPORT_SUCCESS = "achievement_import_success"
private static let KEY_ACHIEVEMENT_NOTIFICATION_ON = "achievement_notification_on"
private static let KEY_ACHIEVEMENT_WIDGET_ADD = "achievement_widget_add"
private static let KEY_ACHIEVEMENT_SHARE_SUCCESS = "achievement_share_success"
private static let KEY_ACHIEVEMENT_EXPORT_BACKUP = "achievement_export_backup"
private static let KEY_ACHIEVEMENT_IMPORT_TWICE = "achievement_import_twice"
private static let KEY_ACHIEVEMENT_DELETE_ONCE = "achievement_delete_once"
private static let KEY_ACHIEVEMENT_IMPORT_BACKUP = "achievement_import_backup"
private static let KEY_ACHIEVEMENT_IMPORT_COUNT = "achievement_import_count"
```

- [ ] **Step 2: 实现 8 个成就标记的 getter/setter**

在 `AppPrefs` 类适当位置添加（与现有方法风格一致）：

```swift
// MARK: - Game Center 成就

func isAchievementImportSuccessUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_IMPORT_SUCCESS)
}

func setAchievementImportSuccessUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_IMPORT_SUCCESS)
}

func isAchievementNotificationOnUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_NOTIFICATION_ON)
}

func setAchievementNotificationOnUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_NOTIFICATION_ON)
}

func isAchievementWidgetAddUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_WIDGET_ADD)
}

func setAchievementWidgetAddUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_WIDGET_ADD)
}

func isAchievementShareSuccessUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_SHARE_SUCCESS)
}

func setAchievementShareSuccessUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_SHARE_SUCCESS)
}

func isAchievementExportBackupUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_EXPORT_BACKUP)
}

func setAchievementExportBackupUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_EXPORT_BACKUP)
}

func isAchievementImportTwiceUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_IMPORT_TWICE)
}

func setAchievementImportTwiceUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_IMPORT_TWICE)
}

func isAchievementDeleteOnceUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_DELETE_ONCE)
}

func setAchievementDeleteOnceUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_DELETE_ONCE)
}

func isAchievementImportBackupUnlocked() -> Bool {
    return defaults.bool(forKey: Self.KEY_ACHIEVEMENT_IMPORT_BACKUP)
}

func setAchievementImportBackupUnlocked(_ unlocked: Bool) {
    defaults.set(unlocked, forKey: Self.KEY_ACHIEVEMENT_IMPORT_BACKUP)
}
```

- [ ] **Step 3: 实现导入计数管理**

```swift
func getAchievementImportCount() -> Int {
    return defaults.integer(forKey: Self.KEY_ACHIEVEMENT_IMPORT_COUNT)
}

func incrementAchievementImportCount() -> Int {
    let current = getAchievementImportCount()
    let newCount = current + 1
    defaults.set(newCount, forKey: Self.KEY_ACHIEVEMENT_IMPORT_COUNT)
    return newCount
}
```

- [ ] **Step 4: Commit**

```bash
git add Sleepy/data/AppPrefs.swift
git commit -m "feat(gamecenter): 添加成就本地标记到 AppPrefs

- 8 个成就解锁标记 getter/setter
- 导入计数管理 (incrementAchievementImportCount)
- 为 GameCenterManager 和 AchievementTracker 提供持久化

ref Game Center 成就系统设计"
```

---

### Task 2: 创建 GameCenterManager

**Files:**
- Create: `Sleepy/gamecenter/GameCenterManager.swift`

**Interfaces:**
- Produces:
  - `GameCenterManager.shared: GameCenterManager` (单例)
  - `authenticate() -> Void` (异步认证)
  - `unlockAchievement(id: String, completion: ((Bool) -> Void)?)` (上报成就)
  - `isAuthenticated: Bool { get }` (认证状态)

- [ ] **Step 1: 创建目录和文件骨架**

```bash
mkdir -p Sleepy/gamecenter
```

创建文件 `Sleepy/gamecenter/GameCenterManager.swift`：

```swift
import Foundation
import GameKit

/// Game Center 管理器：负责认证和成就上报
final class GameCenterManager {
    static let shared = GameCenterManager()
    
    private var _isAuthenticated = false
    
    private init() {}
    
    var isAuthenticated: Bool {
        return _isAuthenticated
    }
    
    // 将在后续步骤实现
}
```

- [ ] **Step 2: 实现认证逻辑**

```swift
/// App 启动时调用，自动认证 Game Center
func authenticate() {
    GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
        if let viewController = viewController {
            // 需要显示登录界面（iOS 通常自动处理，这里静默忽略）
            // 生产环境不主动弹登录框，尊重用户选择
            print("[GameCenter] Authentication UI available, but not shown")
            self?._isAuthenticated = false
        } else if let error = error {
            // 认证失败：用户未登录或拒绝
            print("[GameCenter] Authentication failed: \(error.localizedDescription)")
            self?._isAuthenticated = false
        } else {
            // 认证成功
            if GKLocalPlayer.local.isAuthenticated {
                print("[GameCenter] Authenticated as \(GKLocalPlayer.local.displayName ?? "Unknown")")
                self?._isAuthenticated = true
            } else {
                print("[GameCenter] Not authenticated")
                self?._isAuthenticated = false
            }
        }
    }
}
```

- [ ] **Step 3: 实现成就上报逻辑**

```swift
/// 上报成就解锁到 Game Center
/// - Parameters:
///   - id: 成就 ID（与 App Store Connect 配置一致）
///   - completion: 完成回调，true 表示成功
func unlockAchievement(id: String, completion: ((Bool) -> Void)? = nil) {
    guard isAuthenticated else {
        print("[GameCenter] Cannot unlock achievement '\(id)': not authenticated")
        completion?(false)
        return
    }
    
    let achievement = GKAchievement(identifier: id)
    achievement.percentComplete = 100.0
    achievement.showsCompletionBanner = true  // 显示系统成就通知
    
    GKAchievement.report([achievement]) { error in
        if let error = error {
            print("[GameCenter] Failed to unlock achievement '\(id)': \(error.localizedDescription)")
            completion?(false)
        } else {
            print("[GameCenter] Successfully unlocked achievement '\(id)'")
            completion?(true)
        }
    }
}
```

- [ ] **Step 4: 添加 DEBUG 重置功能**

```swift
#if DEBUG
/// 重置所有成就进度（仅开发用）
/// 注意：需要在设置中删除 Game Center 沙盒数据才能完全重置
func resetAllAchievements() {
    GKAchievement.loadAchievements { achievements, error in
        guard let achievements = achievements, error == nil else {
            print("[GameCenter] Failed to load achievements for reset")
            return
        }
        
        GKAchievement.resetAchievements { error in
            if let error = error {
                print("[GameCenter] Failed to reset achievements: \(error.localizedDescription)")
            } else {
                print("[GameCenter] All achievements reset")
            }
        }
    }
}
#endif
```

- [ ] **Step 5: Commit**

```bash
git add Sleepy/gamecenter/GameCenterManager.swift
git commit -m "feat(gamecenter): 实现 GameCenterManager

- authenticate() App 启动时自动认证
- unlockAchievement() 上报成就到 Game Center
- isAuthenticated 认证状态查询
- DEBUG 模式提供重置功能

ref Game Center 成就系统设计"
```

---

### Task 3: 创建 AchievementTracker

**Files:**
- Create: `Sleepy/gamecenter/AchievementTracker.swift`

**Interfaces:**
- Consumes:
  - `GameCenterManager.shared.isAuthenticated: Bool`
  - `GameCenterManager.shared.unlockAchievement(id:completion:)`
  - `AppPrefs.shared.isAchievementXXXUnlocked() -> Bool`
  - `AppPrefs.shared.setAchievementXXXUnlocked(_ unlocked: Bool)`
  - `AppPrefs.shared.incrementAchievementImportCount() -> Int`
- Produces:
  - `AchievementTracker.shared: AchievementTracker`
  - `checkImportSuccess()`
  - `checkNotificationOn()`
  - `checkWidgetAdd()`
  - `checkShareSuccess()`
  - `checkExportBackup()`
  - `checkDeleteOnce()`
  - `checkImportBackup()`

- [ ] **Step 1: 创建文件骨架**

创建 `Sleepy/gamecenter/AchievementTracker.swift`：

```swift
import Foundation

/// 成就追踪器：检查触发条件并协调本地标记 + Game Center 上报
final class AchievementTracker {
    static let shared = AchievementTracker()
    
    // 成就 ID 常量（与 App Store Connect 配置一致）
    private enum AchievementID {
        static let importSuccess = "import_success"
        static let notificationOn = "notification_on"
        static let widgetAdd = "widget_add_success"
        static let shareSuccess = "share_success"
        static let exportBackup = "export_backup"
        static let importTwice = "import_twice"
        static let deleteOnce = "delete_once"
        static let importBackup = "import_backup"
    }
    
    private let prefs = AppPrefs.shared
    private let gameCenter = GameCenterManager.shared
    
    private init() {}
    
    // 将在后续步骤实现各 check 方法
}
```

- [ ] **Step 2: 实现通用解锁逻辑**

```swift
/// 通用成就解锁逻辑：检查本地标记 → 上报 Game Center → 写本地标记
private func unlock(
    achievementID: String,
    isUnlocked: @escaping () -> Bool,
    setUnlocked: @escaping (Bool) -> Void
) {
    // 已解锁则跳过
    guard !isUnlocked() else {
        return
    }
    
    // 上报到 Game Center
    gameCenter.unlockAchievement(id: achievementID) { success in
        // 无论上报成功与否，都写本地标记，避免重复触发
        setUnlocked(true)
    }
}
```

- [ ] **Step 3: 实现 8 个成就触发方法**

```swift
// MARK: - 成就触发检查

/// 首次导入成功
func checkImportSuccess() {
    unlock(
        achievementID: AchievementID.importSuccess,
        isUnlocked: prefs.isAchievementImportSuccessUnlocked,
        setUnlocked: prefs.setAchievementImportSuccessUnlocked
    )
    
    // 同时增加导入计数，检查 import_twice
    let count = prefs.incrementAchievementImportCount()
    if count >= 2 {
        unlock(
            achievementID: AchievementID.importTwice,
            isUnlocked: prefs.isAchievementImportTwiceUnlocked,
            setUnlocked: prefs.setAchievementImportTwiceUnlocked
        )
    }
}

/// 开启提醒
func checkNotificationOn() {
    unlock(
        achievementID: AchievementID.notificationOn,
        isUnlocked: prefs.isAchievementNotificationOnUnlocked,
        setUnlocked: prefs.setAchievementNotificationOnUnlocked
    )
}

/// 添加 Widget
func checkWidgetAdd() {
    unlock(
        achievementID: AchievementID.widgetAdd,
        isUnlocked: prefs.isAchievementWidgetAddUnlocked,
        setUnlocked: prefs.setAchievementWidgetAddUnlocked
    )
}

/// 分享成功
func checkShareSuccess() {
    unlock(
        achievementID: AchievementID.shareSuccess,
        isUnlocked: prefs.isAchievementShareSuccessUnlocked,
        setUnlocked: prefs.setAchievementShareSuccessUnlocked
    )
}

/// 导出备份
func checkExportBackup() {
    unlock(
        achievementID: AchievementID.exportBackup,
        isUnlocked: prefs.isAchievementExportBackupUnlocked,
        setUnlocked: prefs.setAchievementExportBackupUnlocked
    )
}

/// 首次删除课表
func checkDeleteOnce() {
    unlock(
        achievementID: AchievementID.deleteOnce,
        isUnlocked: prefs.isAchievementDeleteOnceUnlocked,
        setUnlocked: prefs.setAchievementDeleteOnceUnlocked
    )
}

/// 导入备份
func checkImportBackup() {
    unlock(
        achievementID: AchievementID.importBackup,
        isUnlocked: prefs.isAchievementImportBackupUnlocked,
        setUnlocked: prefs.setAchievementImportBackupUnlocked
    )
}
```

- [ ] **Step 4: Commit**

```bash
git add Sleepy/gamecenter/AchievementTracker.swift
git commit -m "feat(gamecenter): 实现 AchievementTracker

- 8 个成就触发检查方法
- 本地标记 + Game Center 上报协调
- 导入计数自动检查 import_twice

ref Game Center 成就系统设计"
```

---

### Task 4: App 启动时初始化 Game Center

**Files:**
- Modify: `Sleepy/SleepyApp.swift`

**Interfaces:**
- Consumes: `GameCenterManager.shared.authenticate()`

- [ ] **Step 1: 在 App 初始化时调用认证**

定位 `SleepyApp.swift` 中的 `init()` 或 `@main` 入口，添加：

```swift
import GameKit

@main
struct SleepyApp: App {
    init() {
        // ... 现有初始化代码 ...
        
        // Game Center 认证
        GameCenterManager.shared.authenticate()
    }
    
    // ... 其余代码 ...
}
```

- [ ] **Step 2: Commit**

```bash
git add Sleepy/SleepyApp.swift
git commit -m "feat(gamecenter): App 启动时初始化 Game Center

- 自动认证 Game Center
- 静默处理，不影响 App 正常使用

ref Game Center 成就系统设计"
```

---

### Task 5: 集成导入成功成就

**Files:**
- Modify: `Sleepy/data/jw/JwImportFlow.swift`

**Interfaces:**
- Consumes:
  - `AchievementTracker.shared.checkImportSuccess()`
  - `AchievementTracker.shared.checkImportBackup()`

- [ ] **Step 1: 定位导入成功回调**

查找 `JwImportFlow.swift` 中导入成功的回调位置（通常在 `onSuccess` 或类似方法中）

- [ ] **Step 2: 添加成就触发**

在导入成功后添加：

```swift
// 导入成功后触发成就
AchievementTracker.shared.checkImportSuccess()

// 如果是 WakeUP 分享码导入，还要触发备份导入成就
if isWakeUpImport {  // 根据实际代码逻辑判断
    AchievementTracker.shared.checkImportBackup()
}
```

- [ ] **Step 3: Commit**

```bash
git add Sleepy/data/jw/JwImportFlow.swift
git commit -m "feat(gamecenter): 导入成功触发成就

- import_success: 首次导入
- import_twice: 累计导入 2 次（自动检查）
- import_backup: WakeUP 分享码导入

ref Game Center 成就系统设计"
```

---

### Task 6: 集成提醒开关成就

**Files:**
- Modify: `Sleepy/ui/screen/mine/ReminderSettingsScreen.swift` (或实际提醒设置位置)

**Interfaces:**
- Consumes: `AchievementTracker.shared.checkNotificationOn()`

- [ ] **Step 1: 定位提醒开关代码**

查找提醒开关（`@State` 或 `Toggle`）的位置

- [ ] **Step 2: 在开关变更时检查成就**

```swift
Toggle("课程提醒", isOn: $reminderEnabled)
    .onChange(of: reminderEnabled) { newValue in
        // 原有逻辑：保存偏好
        prefs.setReminderEnabled(newValue)
        
        // 新增：开启时触发成就
        if newValue {
            AchievementTracker.shared.checkNotificationOn()
        }
    }
```

- [ ] **Step 3: Commit**

```bash
git add Sleepy/ui/screen/mine/ReminderSettingsScreen.swift
git commit -m "feat(gamecenter): 开启提醒触发成就

- notification_on: 提醒开关 false → true

ref Game Center 成就系统设计"
```

---

### Task 7: 集成删除课表成就

**Files:**
- Modify: `Sleepy/ui/screen/mine/AllTablesScreen.swift` (或 Repository 层)

**Interfaces:**
- Consumes: `AchievementTracker.shared.checkDeleteOnce()`

- [ ] **Step 1: 定位删除课表成功位置**

查找 `TimeTableDao.delete()` 或 `ScheduleRepository` 删除成功的回调

- [ ] **Step 2: 删除成功后触发成就**

```swift
// 删除成功后
try db.timeTableDao.delete(id)
AchievementTracker.shared.checkDeleteOnce()
```

或在 UI 层删除成功回调中：

```swift
viewModel.deleteTable(id) { success in
    if success {
        AchievementTracker.shared.checkDeleteOnce()
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sleepy/ui/screen/mine/AllTablesScreen.swift
git commit -m "feat(gamecenter): 删除课表触发成就

- delete_once: 首次删除任意课表

ref Game Center 成就系统设计"
```

---

### Task 8: 集成分享、导出、Widget 成就（待定位）

**Files:**
- Modify: 分享功能触发点（需定位）
- Modify: 导出备份触发点（需定位）
- Modify: Widget 检测逻辑（需定位）

**Interfaces:**
- Consumes:
  - `AchievementTracker.shared.checkShareSuccess()`
  - `AchievementTracker.shared.checkExportBackup()`
  - `AchievementTracker.shared.checkWidgetAdd()`

- [ ] **Step 1: 定位分享功能**

查找分享弹窗显示代码（`UIActivityViewController` 或 `ShareSheet`）

```swift
// 分享弹窗显示时
let activityVC = UIActivityViewController(...)
present(activityVC, animated: true) {
    AchievementTracker.shared.checkShareSuccess()
}
```

或 SwiftUI：

```swift
.sheet(isPresented: $showShareSheet) {
    ShareSheet(...)
        .onAppear {
            AchievementTracker.shared.checkShareSuccess()
        }
}
```

- [ ] **Step 2: 定位导出备份**

查找导出文件保存成功的位置：

```swift
// 导出成功后
exportBackupFile { success in
    if success {
        AchievementTracker.shared.checkExportBackup()
    }
}
```

- [ ] **Step 3: 定位 Widget 检测**

在 `SceneDelegate` 或 `AppDelegate` 的 `sceneWillEnterForeground` 中添加：

```swift
import WidgetKit

func sceneWillEnterForeground(_ scene: UIScene) {
    // 检查是否有 Widget
    WidgetCenter.shared.getCurrentConfigurations { result in
        if case .success(let widgets) = result, !widgets.isEmpty {
            AchievementTracker.shared.checkWidgetAdd()
        }
    }
}
```

- [ ] **Step 4: Commit（分批或合并）**

```bash
git add <modified-files>
git commit -m "feat(gamecenter): 集成分享/导出/Widget 成就

- share_success: 分享弹窗显示
- export_backup: 导出备份成功
- widget_add_success: 检测到 Widget

ref Game Center 成就系统设计"
```

---

### Task 9: 验证和测试

- [ ] **Step 1: 编译检查**

```bash
cd /Users/kerrylee/sleepy-ios/.worktrees/integration-parity-v1063
xcodebuild -project Sleepy.xcodeproj -scheme Sleepy -destination 'platform=iOS Simulator,name=iPhone 15' build
```

预期：编译成功，无错误

- [ ] **Step 2: 在模拟器中测试（手动）**

1. 登录 Game Center 沙盒账号
2. 逐个触发 8 个成就条件
3. 验证系统通知弹出
4. 检查 Game Center App 显示成就进度

- [ ] **Step 3: 检查本地标记持久化**

```swift
// DEBUG 代码验证
print("Import success unlocked: \(AppPrefs.shared.isAchievementImportSuccessUnlocked())")
print("Import count: \(AppPrefs.shared.getAchievementImportCount())")
```

- [ ] **Step 4: 边界情况验证**

- 未登录 Game Center → App 正常使用，无崩溃
- 重复触发同一成就 → 不重复上报
- 网络断开 → 本地标记仍生效

---

## 实现顺序总结

1. ✅ Task 1: AppPrefs 扩展（基础设施）
2. ✅ Task 2: GameCenterManager（认证和上报）
3. ✅ Task 3: AchievementTracker（触发逻辑）
4. ✅ Task 4: App 启动初始化
5. ✅ Task 5-8: 集成到 8 个触发点
6. ✅ Task 9: 验证和测试

## 注意事项

- **App Store Connect 配置**：8 个成就必须在提交前配置完成，ID 完全匹配
- **隐私合规**：Game Center 是可选功能，Info.plist 无需特殊权限
- **测试环境**：使用 Game Center 沙盒账号测试
- **DEBUG 重置**：`GameCenterManager.shared.resetAllAchievements()` 仅开发用
