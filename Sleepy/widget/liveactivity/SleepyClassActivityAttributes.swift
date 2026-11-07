// SleepyClassActivityAttributes.swift — 课程灵动岛实况活动属性包 (v1.0.64)
//
// 纯 Foundation + ActivityKit；Sleepy(主 App) 与 SleepyWidget(扩展) 共源编译。
// ActivityKit 跨进程匹配按类型名 + 归档表达 —— Apple 官方样例同款手法:
// 同一 .swift 文件编进两个 target 各一份同名类型即桥接成功。
//
// iOS 16.1+ 门控(部署目标 15.6): 调用方一律 #available / @available 守卫。

import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct SleepyClassActivityAttributes: ActivityAttributes {

    /// 单节课快照 — 只存呈现所需最小字段(活动内容随状态整体归档)。
    public struct Entry: Codable, Hashable {
        public let name: String
        public let room: String
        public let start: Date
        public let end: Date

        public init(name: String, room: String, start: Date, end: Date) {
            self.name = name
            self.room = room
            self.start = start
            self.end = end
        }
    }

    /// 当前活动段内的全部课程(段 = 相邻课间隔 ≤60min 的一组, 见 ClassDayActivityCore)。
    public struct ContentState: Codable, Hashable {
        public let tableName: String
        public let entries: [Entry]

        public init(tableName: String, entries: [Entry]) {
            self.tableName = tableName
            self.entries = entries
        }
    }

    public init() {}
}
