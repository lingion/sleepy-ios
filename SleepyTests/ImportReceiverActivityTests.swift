// ImportReceiverActivityTests.swift — ← ImportReceiverActivity.kt 外部打开读取逻辑
// (Android 侧无对应单测; 此处锁定可测纯逻辑: file:// 复制读删 / 空白判定分支)
// 覆盖: readText 正常文本 / UTF-8 非法字节→nil(≙ Android 抛错→catch) / 空文件→""
//       + 消费闸的 isNullOrBlank 等价判定(trim 后空 → finishWithError("empty") 路径)

import XCTest
@testable import Sleepy

final class ImportReceiverActivityTests: XCTestCase {

    private func makeTempFile(named name: String, bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // ≙ Android: file:// URI → 复制 cacheDir → readText → delete
    func testReadTextFromFileURLReturnsContent() throws {
        let text = "{\"courses\":[]}"
        let url = try makeTempFile(named: "ri_ok.json", bytes: Data(text.utf8))
        let got = try ImportReceiverActivity.readText(from: url)
        XCTAssertEqual(got, text)
        // 复制体读后即删: temporaryDirectory 里不应残留 shared_import_*.json
        // (源文件由本测试创建, 与复制体不同名, 不会误判)
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil).filter {
                $0.lastPathComponent.hasPrefix("shared_import_")
            }
        XCTAssertTrue(leftovers.isEmpty, "shared_import 复制体应已删除, 残留: \(leftovers)")
    }

    // ≙ Android: 空文件 → text.isBlank → finishWithError("empty") (静默回主界面)
    func testEmptyFileTriggersBlankBranch() throws {
        let url = try makeTempFile(named: "ri_empty.json", bytes: Data())
        let got = try ImportReceiverActivity.readText(from: url)
        XCTAssertEqual(got ?? "", "")
        let blank = (got ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        XCTAssertTrue(blank)
    }

    // ≙ Android: 全空白文本同样走 empty 分支
    func testWhitespaceOnlyTriggersBlankBranch() throws {
        let url = try makeTempFile(named: "ri_ws.json",
                                   bytes: Data("  \n\t ".utf8))
        let got = try ImportReceiverActivity.readText(from: url)
        let blank = (got ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        XCTAssertTrue(blank)
    }

    // ≙ Android: 非法 UTF-8 字节 → readText 抛错 → catch → finishWithError(msg);
    //   iOS String(contentsOf:.utf8) 抛/返回 nil → blank 判定成立, 可见结果一致
    func testInvalidUTF8DoesNotProduceNonBlankText() throws {
        let bad = Data([0xFF, 0xFE, 0x00, 0x80])
        let url = try makeTempFile(named: "ri_bad.json", bytes: bad)
        let got: String?
        do {
            got = try ImportReceiverActivity.readText(from: url)
        } catch {
            got = nil // Android 同路径: 异常外抛 → catch → finishWithError
        }
        let blank = (got ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        XCTAssertTrue(blank, "非法编码不得产生可导入文本 (got=\(got ?? "nil"))")
    }
}
