import XCTest
@testable import Sleepy

/// F080 (JwImportFlow v1.0.61 对齐) 纯逻辑回归锁。
///
/// 锁 DiagMapper 的 UNKNOWN_EMPTY 网络提示尾(F080 issue #15):
/// Android mapImpl 对 UNKNOWN_EMPTY 返回 "$base（features）$hintPart" —
/// 校园网限制主机(v1.0.46+ 24 校)与强智系协议在 unknownEmpty 分类下也必须
/// 保留 jw_diag_campus_vpn_hint / jw_diag_qz_vpn_hint 尾; iOS 旧实现提前
/// `return base` 把尾丢了。JwImportActivityDiagnosticsTest(Android) 同源语义。
final class JwImportFlowTests: XCTestCase {

    private let linyi = JwSchoolInfo(sortKey: "L", name: "临沂大学",
                                     url: "http://jwgl.lyu.edu.cn/jwglxt",
                                     type: JwProtocol.TYPE_ZF_NEW, sortKeyFull: "linyi")
    private let sdust = JwSchoolInfo(sortKey: "S", name: "山东科技",
                                     url: "http://jwgl.sdust.edu.cn",
                                     type: JwProtocol.TYPE_QZ, sortKeyFull: "shandongkeji")
    private let pku = JwSchoolInfo(sortKey: "B", name: "北京大学",
                                   url: "https://elective.pku.edu.cn",
                                   type: JwProtocol.TYPE_PKU, sortKeyFull: "beida")

    private func diag(_ cat: JwParseDiagnostics.Category,
                      features: [String] = ["kbtable", "img_in_table", "vpn"]) -> JwParseDiagnostics.Result {
        JwParseDiagnostics.Result(category: cat, attempts: [], matchedFeatures: features,
                                  courseCount: 0, userMessage: "")
    }

    /// UNKNOWN_EMPTY + 校园网限制主机 → 特征回显 + 校园网/VPN 提示尾都在。
    func testUnknownEmptyKeepsCampusVpnHint() {
        let msg = DiagMapper.map(diag(.unknownEmpty), linyi)
        XCTAssertTrue(msg.contains("kbtable") || msg.contains("img_in_table"),
                      "UNKNOWN_EMPTY 应回显诊断特征: \(msg)")
        XCTAssertTrue(msg.contains("校园网") || msg.contains("VPN"),
                      "UNKNOWN_EMPTY 不得吞掉校园网提示尾(issue#15 回归): \(msg)")
    }

    /// UNKNOWN_EMPTY + 强智系协议 → 强智专属提示尾在。
    func testUnknownEmptyKeepsQzHint() {
        let msg = DiagMapper.map(diag(.unknownEmpty), sdust)
        XCTAssertTrue(msg.contains("强智") || msg.contains("重新登录"),
                      "强智校 UNKNOWN_EMPTY 应含强智提示尾: \(msg)")
    }

    /// UNKNOWN_EMPTY + 普通校 → 只有 base, 无提示尾。
    func testUnknownEmptyGenericSchoolHasNoHintTail() {
        let msg = DiagMapper.map(diag(.unknownEmpty), pku)
        XCTAssertTrue(msg.contains("kbtable"), "特征仍应回显: \(msg)")
        XCTAssertFalse(msg.contains("校园网"), "北大不应触发校园网提示: \(msg)")
        XCTAssertFalse(msg.contains("强智"), "北大不应触发强智提示: \(msg)")
    }

    /// 提示尾格式与 Android 一致: base + "\n\n" + hint(双换行分隔, 非拼接同段)。
    func testHintTailSeparatedByDoubleNewline() {
        let msg = DiagMapper.map(diag(.unknownEmpty), linyi)
        XCTAssertTrue(msg.contains("\n\n"), "提示尾应以空行分隔(← Android hintPart = \"\\n\\n$schoolHint\"): \(msg)")
    }

    /// v1.0.61 新收录的受限主机(矿大北京/石河子/广州医科)在 unknownEmpty 与
    /// 其他分类下同样获得校园网提示 — 锁清单不因分类分叉。
    func testNewCampusHostsCoveredInUnknownEmpty() {
        for host in ["jwxt.cumtb.edu.cn", "jwgl.shzu.edu.cn", "jwgl.gzhmu.edu.cn"] {
            let school = JwSchoolInfo(sortKey: "T", name: "测试校", url: "http://\(host)/x",
                                      type: JwProtocol.TYPE_ZF_NEW, sortKeyFull: "test")
            let msg = DiagMapper.map(diag(.unknownEmpty), school)
            XCTAssertTrue(msg.contains("校园网") || msg.contains("VPN"),
                          "\(host) UNKNOWN_EMPTY 应含校园网提示尾: \(msg)")
        }
    }
}
