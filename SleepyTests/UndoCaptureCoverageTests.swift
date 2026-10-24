// UndoCaptureCoverageTests.swift — ← UndoCaptureCoverageTest.kt (逐行翻译, GPL-3.0)
// 撤回快照覆盖契约 — 用户 2026-09-10 报「编辑课表后没有撤回按钮」。
//
// 根因: issue#22 (3f76309) 把编辑课程保存从 updateCourseGroup(自带 capture)
// 换成 applyDiff, 其 KDoc 要求"调用前必须已 captureForUndo"但无人履行 →
// 编辑课程不产生快照 → 撤回按钮(ScheduleScreen 按 hasSnapshot 显隐)不亮。
//
// 沿用安卓 WidgetInfoXmlContractTest 的"读源头文件当契约"先例: 扫
// ScheduleRepository.swift 源码, 断言每个写库的公开方法体内都出现 captureForUndo()。
// 路径经 #filePath(编译期=本文件绝对路径)相对定位工程内源文件; 真机测试宿主
// 上源文件不在盘(模拟器可读宿主文件), 此时显式 XCTSkip 而非静默通过。

import XCTest

final class UndoCaptureCoverageTests: XCTestCase {

    /// ScheduleRepository.swift 的 URL: 相对本测试源文件定位工程根。
    private var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SleepyTests/
            .deletingLastPathComponent()   // 工程根
            .appendingPathComponent("Sleepy/data/repository/ScheduleRepository.swift")
    }

    /// 会写课表数据的公开方法 — 漏一个 capture, 对应动作的撤回按钮就消失一次。
    /// 清单 = ScheduleRepository.swift 实际写库方法集(安卓 14 个共有方法 +
    /// issue#40 节次表写路径 + iOS 侧 setGroupSourceColor 落库路径;
    /// updateTableRemappingCourses 为安卓独有, iOS 无对应方法)。
    private let mustCapture = [
        "insertTable", "updateTable", "deleteTable",
        "insertPeriodTable", "copyPeriodTable", "copyPeriodTableAs",
        "bindPeriodTable", "updatePeriodTable", "savePeriodTable", "deletePeriodTable",
        "insertCourse", "insertCourses", "insertCoursesKeepingGroups",
        "replaceCoursesKeepingGroups", "updateCourse", "updateCourseGroup",
        "setGroupSourceColor", "applyDiff", "deleteCourse", "deleteCourseGroup",
        "replaceCourses"
    ]

    /// 正则在 text 中找第一处匹配(NSString 坐标系)。
    private func firstRange(of pattern: String, in text: String, from location: Int = 0) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let start = min(max(0, location), ns.length)
        let range = NSRange(location: start, length: ns.length - start)
        return regex.firstMatch(in: text, options: [], range: range)?.range
    }

    /// 方法签名起点 → 下一个方法声明之间的源码段(语义同 Kotlin segmentOf)。
    /// 找不到方法签名时返回 nil(Kotlin 用 error() 抛出 → 这里契约失败处理)。
    private func segmentOf(_ method: String, in source: String) -> String? {
        guard let sig = firstRange(of: "func\\s+\(method)\\s*\\(", in: source) else { return nil }
        // 从签名 +20 之后找下一个方法声明起点(与 Kotlin find(startIndex = start + 20) 同语义)
        let next = firstRange(of: "\n\\s*(private\\s+)?func\\s+\\w+", in: source,
                              from: sig.location + 20)?.location ?? (source as NSString).length
        return (source as NSString).substring(with: NSRange(location: sig.location,
                                                            length: max(0, next - sig.location)))
    }

    func testEveryPublicWriteMethodCapturesUndoSnapshot() throws {
        guard (try? String(contentsOf: repositoryURL, encoding: .utf8)) != nil else {
            throw XCTSkip("源文件不在盘(真机宿主?) — 契约测试需在模拟器/主机构建运行: \(repositoryURL.path)")
        }
        let source = try String(contentsOf: repositoryURL, encoding: .utf8)
        var missing: [String] = []
        var absent: [String] = []
        for method in mustCapture {
            guard let seg = segmentOf(method, in: source) else { absent.append(method); continue }
            if !seg.contains("captureForUndo()") { missing.append(method) }
        }
        XCTAssertTrue(absent.isEmpty,
            "ScheduleRepository 缺少方法 \(absent) — 契约清单需同步")
        XCTAssertTrue(missing.isEmpty,
            "公开写方法缺少 captureForUndo: \(missing) — 这些动作的撤回按钮将不亮(2026-09-10 编辑课程翻车)")
    }

    func testApplyDiffCapturesBeforeFirstDaoWrite() throws {
        guard let source = try? String(contentsOf: repositoryURL, encoding: .utf8) else {
            throw XCTSkip("源文件不在盘(真机宿主?) — 契约测试需在模拟器/主机构建运行: \(repositoryURL.path)")
        }
        guard let segString = segmentOf("applyDiff", in: source).map({ $0 as NSString }) else {
            XCTFail("ScheduleRepository 缺少方法 applyDiff — 契约清单需同步")
            return
        }
        // NSString.range(of:) 找不到返回 NSNotFound(=Int.max), 必须先归一化为 -1(Kotlin indexOf 语义)
        func idx(_ needle: String) -> Int {
            let r = segString.range(of: needle)
            return r.location == NSNotFound ? -1 : r.location
        }
        let captureAt = idx("captureForUndo()")
        let firstWrite = ["deleteByIds", "updateAll", "insertAll"]
            .map(idx).filter { $0 >= 0 }.min() ?? Int.max
        XCTAssertTrue(captureAt >= 0 && captureAt < firstWrite,
            "applyDiff 必须先 captureForUndo 再动 DAO — 否则编辑课程无快照可撤")
    }
}
