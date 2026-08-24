// AppGroupResolver.swift — AltStore 重签后 App Group ID 解析
// 证据: AltStore 源码 FetchProvisioningProfilesOperation.swift:447 (group ID 加 team 后缀)
//      ResignAppOperation.swift:126 (真实 ID 写入 Info.plist ALTAppGroups key)
// 行为: Xcode 直跑(开发签名)→ 用声明的 group ID;AltStore 侧载 → 读 ALTAppGroups[0]
// ← 对应 Android 无此层(单进程无共享),为 iOS 平台差异新增(SPEC 差异表 #8 附注)

import Foundation

enum AppGroupResolver {
    /// 声明的 group ID(与 entitlements 一致)
    static let declaredID = "group.com.lingion.sleepy.ios"

    /// 运行时真实可用的 group ID。解析失败(无 entitlement)→ nil,调用方回退到沙箱内路径
    static func resolve() -> String? {
        // AltStore 侧载: 重签后真实 group ID 在 ALTAppGroups
        if let alt = Bundle.main.infoDictionary?["ALTAppGroups"] as? [String], !alt.isEmpty {
            return alt[0]
        }
        // Xcode 直跑/模拟器: 声明的 ID 可用性探测
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: declaredID) != nil {
            return declaredID
        }
        return nil
    }

    /// 共享数据库目录(App Group 可用→共享容器;否则→各自沙箱 Documents)
    /// widget 与主 app 各自调用,AltStore 下解析到同一共享容器
    static func sharedDirectory() -> URL {
        if let id = resolve(),
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        // 回退: 沙箱(模拟器无 group 时单进程自洽;真机 AltStore 失败时 app 仍可用,widget 不同步)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
