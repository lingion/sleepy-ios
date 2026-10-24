// JwHnustParserTests.swift — ← JwHnustParserTest.kt (v1.0.61)
//
// 6 个用例逐一对应 Android 侧 JwHnustParserTest：
//   1. hnust_kbtable_hidden_div_6条        (fixture hnust_kbtable_hidden_div.html)
//   2. hnust_empty_kbtable_返回空           (fixture hnust_empty_kbtable.html)
//   3. hnust_login_page_无kbtable返回空不抛 (fixture hnust_login_page.html)
//   4. hnust_style两种写法都识别            (内联字符串)
//   5. hnust_oldQzType1_反向过滤            (内联字符串)
//   6. hnust_构造默认参数为0                (内联字符串)

import XCTest
@testable import Sleepy

final class JwHnustParserTests: XCTestCase {

    // MARK: - Fixture loading

    private func loadHtml(name: String) throws -> String {
        let bundle = Bundle(for: JwHnustParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
            ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1. 主链路: 6 条课程字段逐一核对

    func test_hnust_kbtable_hidden_div_6条() throws {
        let courses = try JwHnustParser(loadHtml(name: "hnust_kbtable_hidden_div"),
                                        oldQzType: 0).generateCourseList()
        XCTAssertEqual(6, courses.count)

        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(0, math.type)
        XCTAssertEqual("张老师", math.teacher)
        XCTAssertEqual("主楼A101", math.room)

        // div id="2-2" → startNode = 2*2-1 = 3；周次 "2-15周,17周" 拆 2 条
        let eng = courses.filter { $0.name == "大学英语" }.sorted { $0.startWeek < $1.startWeek }
        XCTAssertEqual(2, eng.count)
        XCTAssertEqual(2, eng[0].day)
        XCTAssertEqual(3, eng[0].startNode)
        XCTAssertEqual(4, eng[0].endNode)
        XCTAssertEqual(2, eng[0].startWeek)
        XCTAssertEqual(15, eng[0].endWeek)
        XCTAssertEqual(17, eng[1].startWeek)
        XCTAssertEqual(17, eng[1].endWeek)

        // div id="3-3" → startNode=5；id="5-5" → startNode=9
        XCTAssertEqual(5, courses.first { $0.name == "线性代数" }!.startNode)
        let cs = courses.first { $0.name == "计算机基础" }!
        XCTAssertEqual(9, cs.startNode)
        XCTAssertEqual(10, cs.endNode)
        XCTAssertEqual(5, cs.day)
        XCTAssertEqual(5, cs.startWeek)
        XCTAssertEqual(12, cs.endWeek)
    }

    // MARK: - 2/3. 空表与登录页防御

    func test_hnust_empty_kbtable_返回空() throws {
        let courses = try JwHnustParser(loadHtml(name: "hnust_empty_kbtable"),
                                        oldQzType: 0).generateCourseList()
        XCTAssertEqual(0, courses.count)
    }

    func test_hnust_login_page_无kbtable返回空不抛() throws {
        let courses = try JwHnustParser(loadHtml(name: "hnust_login_page"),
                                        oldQzType: 0).generateCourseList()
        XCTAssertEqual(0, courses.count)
    }

    // MARK: - 4. style 两种写法都识别

    func test_hnust_style两种写法都识别() throws {
        // 真实页 "display: none;"（冒号后空格）与 fixture "display:none;"（无空格）必须都能命中
        let withSpace = """
        <html><body><table id="kbtable"><tr>
        <td><div id="1-1" style="display: none;">课A<br>王老师<br>1-10周<br>教室X</div></td>
        <td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>
        </tr></table></body></html>
        """
        let noSpace = withSpace.replacingOccurrences(of: "display: none;", with: "display:none;")
        let c1 = try JwHnustParser(withSpace, oldQzType: 0).generateCourseList()
        let c2 = try JwHnustParser(noSpace, oldQzType: 0).generateCourseList()
        XCTAssertEqual(1, c1.count, "带空格写法应命中")
        XCTAssertEqual(1, c2.count, "无空格写法应命中")
        XCTAssertEqual("课A", c1[0].name)
        XCTAssertEqual(1, c1[0].startNode)
        XCTAssertEqual(2, c1[0].endNode)
        XCTAssertEqual(1, c1[0].day)
        XCTAssertEqual(1, c1[0].startWeek)
        XCTAssertEqual(10, c1[0].endWeek)
    }

    // MARK: - 5. oldQzType=1 反向过滤（东北石油大学模式）

    func test_hnust_oldQzType1_反向过滤() throws {
        // oldQzType=1：style != display:none 的 div 才是课
        let src = """
        <html><body><table id="kbtable"><tr>
        <td><div id="1-1">课B<br>李老师<br>1-8周<br>教室Y</div></td>
        <td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>
        </tr></table></body></html>
        """
        let courses = try JwHnustParser(src, oldQzType: 1).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("课B", courses[0].name)
        // 同一页面用 oldQzType=0 应 0 产出（div 无 display:none 样式）
        XCTAssertEqual(0, try JwHnustParser(src, oldQzType: 0).generateCourseList().count)
    }

    // MARK: - 6. 构造默认参数为 0

    func test_hnust_构造默认参数为0() throws {
        // 默认 oldQzType=0：无 display:none 样式的页面 0 产出
        let plain = #"<html><body><table id="kbtable"><tr><td><div id="1-1">课C<br>师<br>1-2周<br>房</div></td></tr></table></body></html>"#
        XCTAssertEqual(0, try JwHnustParser(plain).generateCourseList().count)
        XCTAssertEqual(1, try JwHnustParser(plain, oldQzType: 1).generateCourseList().count)
    }
}
