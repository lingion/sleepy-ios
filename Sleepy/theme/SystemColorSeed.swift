import Foundation
import SwiftUI

/// 可持久化的不透明 sRGB；没有主屏幕/壁纸来源枚举，避免误报能力。
struct SystemSeedRGB: Codable, Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    init?(red: Double, green: Double, blue: Double, alpha: Double) {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite }),
              alpha >= 0.999, alpha <= 1 else { return nil }
        func byte(_ value: Double) -> UInt8 {
            UInt8((min(1, max(0, value)) * 255).rounded())
        }
        self.init(red: byte(red), green: byte(green), blue: byte(blue))
    }

    static let fallback = SystemSeedRGB(red: 103, green: 80, blue: 164)
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

struct SystemColorSnapshot: Codable, Equatable {
    enum Source: String, Codable { case windowTint, fallback }
    enum FallbackReason: String, Codable { case noWindow, invalidColor, missingSnapshot, invalidSnapshot }

    static let schemaVersion = 1
    static let algorithmVersion = 1 // HSV 模板 + WCAG 相对亮度修正；不是 HCT。
    let schemaVersion: Int
    let algorithmVersion: Int
    let source: Source
    let fallbackReason: FallbackReason?
    let seed: SystemSeedRGB
    let systemDark: Bool
    let increasedContrast: Bool
    let windowID: String?

    init(seed: SystemSeedRGB, systemDark: Bool, increasedContrast: Bool, windowID: String) {
        self.schemaVersion = Self.schemaVersion
        self.algorithmVersion = Self.algorithmVersion
        self.source = .windowTint
        self.fallbackReason = nil
        self.seed = seed
        self.systemDark = systemDark
        self.increasedContrast = increasedContrast
        self.windowID = windowID
    }

    private init(reason: FallbackReason, systemDark: Bool, increasedContrast: Bool, windowID: String?) {
        self.schemaVersion = Self.schemaVersion
        self.algorithmVersion = Self.algorithmVersion
        self.source = .fallback
        self.fallbackReason = reason
        self.seed = .fallback
        self.systemDark = systemDark
        self.increasedContrast = increasedContrast
        self.windowID = windowID
    }

    static func fallback(_ reason: FallbackReason, systemDark: Bool = false,
                         increasedContrast: Bool = false, windowID: String? = nil) -> Self {
        Self(reason: reason, systemDark: systemDark, increasedContrast: increasedContrast, windowID: windowID)
    }

    var isValid: Bool {
        guard schemaVersion == Self.schemaVersion, algorithmVersion == Self.algorithmVersion else { return false }
        switch source {
        case .windowTint: return fallbackReason == nil && !(windowID?.isEmpty ?? true)
        case .fallback: return fallbackReason != nil && seed == .fallback
        }
    }
}

/// 只写独立 key，不发布 AppPrefs 通知，不接触课程 DB。
enum SystemColorSeedStore {
    static let key = "system_color_snapshot_v1"
    static var defaults: UserDefaults {
        if let group = AppGroupResolver.resolve(), let suite = UserDefaults(suiteName: group) { return suite }
        return .standard
    }

    static func read(from defaults: UserDefaults = SystemColorSeedStore.defaults) -> SystemColorSnapshot {
        guard let data = defaults.data(forKey: key) else { return .fallback(.missingSnapshot) }
        guard let value = try? JSONDecoder().decode(SystemColorSnapshot.self, from: data), value.isValid else {
            return .fallback(.invalidSnapshot)
        }
        return value
    }

    @discardableResult
    static func write(_ value: SystemColorSnapshot, to defaults: UserDefaults = SystemColorSeedStore.defaults) -> Bool {
        guard value.isValid, read(from: defaults) != value,
              let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

private struct SystemColorSnapshotKey: EnvironmentKey {
    static let defaultValue: SystemColorSnapshot? = nil
}

extension EnvironmentValues {
    var systemColorSnapshot: SystemColorSnapshot? {
        get { self[SystemColorSnapshotKey.self] }
        set { self[SystemColorSnapshotKey.self] = newValue }
    }
}
