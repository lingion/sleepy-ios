#if !WIDGET_EXT && !WATCH_APP
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
    
    /// App 启动时调用，自动认证 Game Center
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let _ = viewController {
                // 需要显示登录界面 — 静默忽略，不主动弹登录框
                self?._isAuthenticated = false
            } else if let _ = error {
                // 认证失败：用户未登录或拒绝 — 静默处理
                self?._isAuthenticated = false
            } else {
                self?._isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }
    
    /// 上报成就解锁到 Game Center
    /// - Parameters:
    ///   - id: 成就 ID（与 App Store Connect 配置一致）
    ///   - completion: 完成回调，true 表示成功
    func unlockAchievement(id: String, completion: ((Bool) -> Void)? = nil) {
        guard isAuthenticated else {
            completion?(false)
            return
        }
        
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = 100.0
        achievement.showsCompletionBanner = true
        
        GKAchievement.report([achievement]) { error in
            if error == nil {
                print("[GameCenter] Achievement unlocked: \(id)")
            }
            completion?(error == nil)
        }
    }
    
    #if DEBUG
    /// 重置所有成就进度（仅开发用）
    func resetAllAchievements() {
        GKAchievement.resetAchievements { error in
            if let error = error {
                print("[GameCenter] Reset failed: \(error.localizedDescription)")
            } else {
                print("[GameCenter] All achievements reset")
            }
        }
    }
    #endif
}
#endif // !WIDGET_EXT && !WATCH_APP
