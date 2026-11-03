// VendorCapabilityState.swift — ← 原版本 VendorCapabilityState enum
// iOS 端能力枚举与 原版本 不完全同构:
// - 原版本 NOTIFICATION_PERMISSION_REQUIRED → iOS notApplicable (iOS 无厂商 ROM 通知通道概念)
// - iOS 端仅保留语义可移植的子集。

/// 厂商增强通知surface的能力状态 (VendorCapabilityState)
enum VendorCapabilityState {
    case enabled
    case disabled
    case notApplicable   // ← 原 NOTIFICATION_PERMISSION_REQUIRED
    case settingsRequired // ← 原 SETTINGS_REQUIRED
    case notSupported    // ← 原 NOT_SUPPORTED
    case unknown
}
