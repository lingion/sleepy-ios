#if !WIDGET_EXT && !WATCH_APP
import Foundation

/// 成就追踪器：保留本地成就进度，Game Center 暂停使用。
final class AchievementTracker {
    static let shared = AchievementTracker()
    
    private let prefs = AppPrefs.shared
    
    private init() {}
    
    // MARK: - 成就触发检查

    /// 首次导入成功（任何教务系统）
    func checkImportSuccess() {
        unlock(
            isUnlocked: prefs.isAchievementImportSuccessUnlocked,
            setUnlocked: prefs.setAchievementImportSuccessUnlocked
        )
        // 同步增加导入计数，达到 2 次解锁 import_twice
        let count = prefs.incrementAchievementImportCount()
        if count >= 2 {
            unlock(
                isUnlocked: prefs.isAchievementImportTwiceUnlocked,
                setUnlocked: prefs.setAchievementImportTwiceUnlocked
            )
        }
    }
    
    /// 开启课程提醒（master toggle on）
    func checkNotificationOn() {
        unlock(
            isUnlocked: prefs.isAchievementNotificationOnUnlocked,
            setUnlocked: prefs.setAchievementNotificationOnUnlocked
        )
    }
    
    /// 系统实际存在 Widget
    func checkWidgetAdd() {
        unlock(
            isUnlocked: prefs.isAchievementWidgetAddUnlocked,
            setUnlocked: prefs.setAchievementWidgetAddUnlocked
        )
    }
    
    /// 分享弹窗已显示
    func checkShareSuccess() {
        unlock(
            isUnlocked: prefs.isAchievementShareSuccessUnlocked,
            setUnlocked: prefs.setAchievementShareSuccessUnlocked
        )
    }
    
    /// 导出备份文件成功
    func checkExportBackup() {
        unlock(
            isUnlocked: prefs.isAchievementExportBackupUnlocked,
            setUnlocked: prefs.setAchievementExportBackupUnlocked
        )
    }
    
    /// 首次删除任意课表
    func checkDeleteOnce() {
        unlock(
            isUnlocked: prefs.isAchievementDeleteOnceUnlocked,
            setUnlocked: prefs.setAchievementDeleteOnceUnlocked
        )
    }
    
    /// 导入 Sleepy 备份文件成功
    func checkImportBackup() {
        unlock(
            isUnlocked: prefs.isAchievementImportBackupUnlocked,
            setUnlocked: prefs.setAchievementImportBackupUnlocked
        )
    }
    
    // MARK: - 内部通用解锁

    private func unlock(
        isUnlocked: () -> Bool,
        setUnlocked: (Bool) -> Void
    ) {
        guard !isUnlocked() else { return }
        setUnlocked(true)
    }
}
#endif // !WIDGET_EXT && !WATCH_APP
