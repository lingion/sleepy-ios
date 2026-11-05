import Foundation

/// 成就追踪器：检查触发条件并协调本地标记 + Game Center 上报
final class AchievementTracker {
    static let shared = AchievementTracker()
    
    // 成就 ID 常量（与 App Store Connect 配置一致）
    private enum AchievementID {
        static let importSuccess  = "import_success"
        static let notificationOn = "notification_on"
        static let widgetAdd      = "widget_add_success"
        static let shareSuccess   = "share_success"
        static let exportBackup   = "export_backup"
        static let importTwice    = "import_twice"
        static let deleteOnce     = "delete_once"
        static let importBackup   = "import_backup"
    }
    
    private let prefs = AppPrefs.shared
    private let gameCenter = GameCenterManager.shared
    
    private init() {}
    
    // MARK: - 成就触发检查

    /// 首次导入成功（任何教务系统）
    func checkImportSuccess() {
        unlock(
            achievementID: AchievementID.importSuccess,
            isUnlocked: prefs.isAchievementImportSuccessUnlocked,
            setUnlocked: prefs.setAchievementImportSuccessUnlocked
        )
        // 同步增加导入计数，达到 2 次解锁 import_twice
        let count = prefs.incrementAchievementImportCount()
        if count >= 2 {
            unlock(
                achievementID: AchievementID.importTwice,
                isUnlocked: prefs.isAchievementImportTwiceUnlocked,
                setUnlocked: prefs.setAchievementImportTwiceUnlocked
            )
        }
    }
    
    /// 开启课程提醒（master toggle on）
    func checkNotificationOn() {
        unlock(
            achievementID: AchievementID.notificationOn,
            isUnlocked: prefs.isAchievementNotificationOnUnlocked,
            setUnlocked: prefs.setAchievementNotificationOnUnlocked
        )
    }
    
    /// 系统实际存在 Widget
    func checkWidgetAdd() {
        unlock(
            achievementID: AchievementID.widgetAdd,
            isUnlocked: prefs.isAchievementWidgetAddUnlocked,
            setUnlocked: prefs.setAchievementWidgetAddUnlocked
        )
    }
    
    /// 分享弹窗已显示
    func checkShareSuccess() {
        unlock(
            achievementID: AchievementID.shareSuccess,
            isUnlocked: prefs.isAchievementShareSuccessUnlocked,
            setUnlocked: prefs.setAchievementShareSuccessUnlocked
        )
    }
    
    /// 导出备份文件成功
    func checkExportBackup() {
        unlock(
            achievementID: AchievementID.exportBackup,
            isUnlocked: prefs.isAchievementExportBackupUnlocked,
            setUnlocked: prefs.setAchievementExportBackupUnlocked
        )
    }
    
    /// 首次删除任意课表
    func checkDeleteOnce() {
        unlock(
            achievementID: AchievementID.deleteOnce,
            isUnlocked: prefs.isAchievementDeleteOnceUnlocked,
            setUnlocked: prefs.setAchievementDeleteOnceUnlocked
        )
    }
    
    /// 导入 Sleepy 备份文件成功
    func checkImportBackup() {
        unlock(
            achievementID: AchievementID.importBackup,
            isUnlocked: prefs.isAchievementImportBackupUnlocked,
            setUnlocked: prefs.setAchievementImportBackupUnlocked
        )
    }
    
    // MARK: - 内部通用解锁

    private func unlock(
        achievementID: String,
        isUnlocked: () -> Bool,
        setUnlocked: (Bool) -> Void
    ) {
        guard !isUnlocked() else { return }
        // 无论 Game Center 是否成功，立即写本地标记防止重复触发
        setUnlocked(true)
        gameCenter.unlockAchievement(id: achievementID)
    }
}
