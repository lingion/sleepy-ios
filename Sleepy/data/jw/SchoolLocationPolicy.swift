// SchoolLocationPolicy.swift — ← data/jw/SchoolLocationPolicy.kt
// 缓存与新请求的 fix 共享质量检查。年龄用单调钟, 不用墙钟。

import Foundation

enum SchoolLocationMode {
    case precise
    case approximate
}

/// 瞬态采样; 永不持久化。Equatable 对齐 Kotlin data class 的结构相等。
struct SchoolLocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let ageNanos: Int64
}

enum SchoolLocationPolicy {
    private static let maxAgeNanos: Int64 = 30_000_000_000   // 30s in ns

    static func modeForPermissions(coarse: Bool, fine: Bool) -> SchoolLocationMode? {
        if !coarse { return nil }
        return fine ? .precise : .approximate
    }

    /// provider 过滤: 去 passive; approximate 模式排除 GPS。
    /// iOS 端 provider 名映射: "gps"→GPS, "network"→wifi/蜂窝, "fused"→significantLocation。
    static func providers(mode: SchoolLocationMode, available: [String]) -> [String] {
        var seen = Set<String>()
        return available.filter { provider in
            guard provider != "passive" else { return false }
            if mode == .approximate && provider == "gps" { return false }
            return seen.insert(provider).inserted
        }
    }

    static func usable(mode: SchoolLocationMode, fix: SchoolLocationFix) -> Bool {
        return fix.latitude.isFinite && fix.latitude >= -90.0 && fix.latitude <= 90.0
            && fix.longitude.isFinite && fix.longitude >= -180.0 && fix.longitude <= 180.0
            && fix.ageNanos >= 0 && fix.ageNanos <= maxAgeNanos
            && fix.accuracyMeters.isFinite
            && fix.accuracyMeters > 0
            && fix.accuracyMeters <= (mode == .precise ? 1_000.0 : 10_000.0)
    }

    /// approximate 模式的城市查询降精度: 坐标取 2 位小数 + 精度半径 +800m。
    /// 早前 fine 授权不得让 approximate 选择用 fine 坐标。
    /// 取整用 floor(x+0.5) 语义精确对齐 Kotlin Math.round(向 +∞ 破 .5 平局),
    /// Swift 默认 .rounded() 是"远离零"破平局, 负坐标(南/西半球)的 .5 平局会与 Android 差 1。
    static func forCityLookup(mode: SchoolLocationMode, fix: SchoolLocationFix) -> SchoolLocationFix {
        guard mode == .approximate else { return fix }
        let lat = (fix.latitude * 100 + 0.5).rounded(.down) / 100
        let lon = (fix.longitude * 100 + 0.5).rounded(.down) / 100
        return SchoolLocationFix(
            latitude: lat, longitude: lon,
            accuracyMeters: fix.accuracyMeters + 800.0,
            ageNanos: fix.ageNanos
        )
    }

    /// 城市 8 方向采样 — 任一方向落到别的城市即拒绝(边界歧义防御)。
    static func city(index: OfflineSchoolCityIndex, fix: SchoolLocationFix) -> String? {
        guard let city = index.cityAt(latitude: fix.latitude, longitude: fix.longitude) else {
            return nil
        }
        let latitudeRadius = fix.accuracyMeters / 111_320.0
        let longitudeRadius = latitudeRadius / max(cos(fix.latitude * .pi / 180), 0.01)
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            if index.cityAt(
                latitude: fix.latitude + latitudeRadius * sin(angle),
                longitude: fix.longitude + longitudeRadius * cos(angle)
            ) != city {
                return nil
            }
        }
        return city
    }
}
