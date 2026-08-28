// WidgetArchiveLog.swift — widget 归档诊断日志(写入 App Group 共享容器)
//
// 目的:
//   1. UI 测试 WidgetArchivingUITests 验证 5 kind × family 归档成功 — runner
//      沙箱读不了系统日志库, App Group 是 app/widget 共享的唯一可读通道。
//   2. 真机排查 widget 空白/不刷新: 用户描述现象 → 拿这份日志即可定位
//      是 timeline 未触发(无记录)还是归档失败(有记录但 error)。
//      (Android 侧等价物为 logcat, iOS 无控制台时此文件即观测点)
//
// 写入点: 各 Provider.getTimeline 完成前(见各 WidgetView.swift)。
// 文件: AppGroup/widget_archive.log, 追加模式, 每次写入裁剪到 256KB 内。

import Foundation

enum WidgetArchiveLog {
    static func append(kind: String, family: String, result: String) {
        let dir = AppGroupResolver.sharedDirectory()
        let url = dir.appendingPathComponent("widget_archive.log")
        let df = ISO8601DateFormatter()
        let line = "\(df.string(from: Date())) \(kind):\(family) \(result)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            // 超限裁剪: 从尾部保留一半
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
               size > 256 * 1024 {
                try? handle.seek(toOffset: UInt64(size / 2))
                let tail = handle.readDataToEndOfFile()
                try? FileManager.default.removeItem(at: url)
                FileManager.default.createFile(atPath: url.path, contents: tail)
                return
            }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: line.data(using: .utf8))
        }
    }
}
