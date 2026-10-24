// JwPekingParserTests.swift — ← JwPekingParserTest.kt (v1.0.61)
//
// fixture 对应 Android 侧 src/test/resources/jw/pku-bnuz/pku_*.html
// 与 jw/adversarial/pku_iaaa_login_redirect.html（此处按项目内联 fixture 惯例复刻，
// 参照 JwQzIeasParserTests / JwHnustParserTests）。

import XCTest
@testable import Sleepy

final class JwPekingParserTests: XCTestCase {

    // MARK: - Fixtures（脱敏复刻自 Android pku_*.html）

    /// pku_normal.html — 3 行: 高等数学(单时段) + 大学英语(2 个 <br> 时段) + 线性代数(未选跳过)
    private static let pkuNormal = #"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <title>已选课程</title>
</head>
<body>
<table class="datagrid">
  <thead>
    <tr>
      <th>课程名</th><th>课号</th><th>学分</th><th>类别</th><th>教师</th>
      <th>班号</th><th>起止周</th><th>时段</th><th>选课状态</th><th>备注</th><th>操作</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>高等数学</td>
      <td>MATH1001</td>
      <td>4</td>
      <td>必修</td>
      <td>张老师</td>
      <td>001</td>
      <td>1~16</td>
      <td>1~16周<br>1~16周 周一1~2节 教101 教101</td>
      <td>已选</td>
      <td></td>
      <td>退选</td>
    </tr>
    <tr>
      <td>大学英语</td>
      <td>ENG2002</td>
      <td>2</td>
      <td>必修</td>
      <td>李老师</td>
      <td>002</td>
      <td>1~16</td>
      <td>1~16周 周三3~4节 教202 教202<br>1~16周 周五5~6节 教303 教303</td>
      <td>已选</td>
      <td></td>
      <td>退选</td>
    </tr>
    <tr>
      <td>线性代数</td>
      <td>MATH1002</td>
      <td>3</td>
      <td>选修</td>
      <td>王老师</td>
      <td>003</td>
      <td>1~16</td>
      <td>1~16周 周二7~8节 教404 教404</td>
      <td>未选</td>
      <td></td>
      <td>选课</td>
    </tr>
  </tbody>
</table>
</body>
</html>
"""#

    /// pku_single_double_week.html — 单周(大学物理) + 双周(化学实验)
    private static let pkuSingleDoubleWeek = #"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <title>已选课程</title>
</head>
<body>
<table class="datagrid">
  <tbody>
    <tr>
      <td>大学物理</td><td>PHY3001</td><td>3</td><td>必修</td><td>物理老师</td>
      <td>001</td><td>1~16</td>
      <td>1~16周<br>1~16周 周一1~2节(单) 实验楼101 实验楼101</td>
      <td>已选</td><td>单周</td><td>退选</td>
    </tr>
    <tr>
      <td>化学实验</td><td>CHE3002</td><td>2</td><td>必修</td><td>化学老师</td>
      <td>002</td><td>1~16</td>
      <td>1~16周<br>1~16周 周四5~6节(双) 实验楼202 实验楼202</td>
      <td>已选</td><td>双周</td><td>退选</td>
    </tr>
  </tbody>
</table>
</body>
</html>
"""#

    /// pku_missing_fields.html — 四行边界:
    /// 行1 tds<11 跳过；行2 空块跳过；行3 括号兜底 room=实验楼201；行4 状态不含'未' 正常解析
    private static let pkuMissingFields = #"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <title>已选课程</title>
</head>
<body>
<table class="datagrid">
  <tbody>
    <tr>
      <td>体育</td><td>PE1001</td><td>1</td><td>必修</td><td>体育馆老师</td>
      <td>001</td><td>1~16</td>
      <td>1~16周 周四3~4节 体育馆</td>
      <td>已选</td>
    </tr>
    <tr>
      <td>军事理论</td><td>MIL1001</td><td>2</td><td>必修</td><td>军训老师</td>
      <td>001</td><td>1~8</td>
      <td>1~8周<br></td>
      <td>已选</td><td></td><td>退选</td>
    </tr>
    <tr>
      <td>大学物理</td><td>PHY2001</td><td>3</td><td>必修</td><td>物理老师</td>
      <td>001</td><td>1~16</td>
      <td>1~16周 周二5~6节(实验楼201)</td>
      <td>已选</td><td></td><td>退选</td>
    </tr>
    <tr>
      <td>大学英语(二)</td><td>ENG3001</td><td>2</td><td>必修</td><td>英语老师</td>
      <td>001</td><td>1~16</td>
      <td>1~16周 周五7~8节 教305</td>
      <td>退课申请中</td><td></td><td>退选</td>
    </tr>
  </tbody>
</table>
</body>
</html>
"""#

    /// pku_empty.html — datagrid 命中、tbody 空
    private static let pkuEmpty = #"""
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"/><title>已选课程</title></head>
<body>
<table class="datagrid">
  <thead>
    <tr><th>课程名</th></tr>
  </thead>
  <tbody>
  </tbody>
</table>
</body>
</html>
"""#

    /// pku_login.html / adversarial pku_iaaa_login_redirect.html — 无 datagrid 的 iaaa 登录页
    private static let pkuLogin = #"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <title>北京大学统一身份认证网关</title>
</head>
<body>
<form id="loginForm" action="/iaaa/oauth.jsp" method="post">
  <input type="text" name="appID" value="syllabus"/>
  <input type="text" name="userName" placeholder="学号"/>
  <input type="password" name="password" placeholder="密码"/>
  <button type="submit">登录</button>
</form>
<p>请使用北京大学统一身份认证账号登录</p>
</body>
</html>
"""#

    /// 最小 11 列行生成器，tds[7] 时段文本可注入（多 ~ 边界用例用）
    private func row(timeCell: String, status: String = "已选") -> String {
        return """
        <!DOCTYPE html><html><body><table class="datagrid"><tbody><tr>
        <td>边界课</td><td>X</td><td>1</td><td>必修</td><td>老师</td>
        <td>001</td><td>1~16</td>
        <td>\(timeCell)</td>
        <td>\(status)</td><td></td><td>退选</td>
        </tr></tbody></table></body></html>
        """
    }

    // MARK: - A. pku_normal：3 门课 / 未选跳过 / 多时段拆分

    func test_pku_normal_3门课_含未选跳过与多时段拆分() throws {
        let courses = try JwPekingParser(Self.pkuNormal).generateCourseList()
        XCTAssertEqual(3, courses.count)
        XCTAssertTrue(!courses.contains { $0.name == "线性代数" }, "tds[8]=未选 必须跳过")

        let math = courses.first { $0.name == "高等数学" }!
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(0, math.type)
        XCTAssertEqual("张老师", math.teacher)
        XCTAssertEqual("教101", math.room)

        // 大学英语 tds[7] 两个 <br> 时段 → 2 条
        let eng = courses.filter { $0.name == "大学英语" }.sorted { $0.day < $1.day }
        XCTAssertEqual(2, eng.count)
        XCTAssertEqual(3, eng[0].day)
        XCTAssertEqual(3, eng[0].startNode)
        XCTAssertEqual(4, eng[0].endNode)
        XCTAssertEqual("教202", eng[0].room)
        XCTAssertEqual(5, eng[1].day)
        XCTAssertEqual(5, eng[1].startNode)
        XCTAssertEqual(6, eng[1].endNode)
        XCTAssertEqual("教303", eng[1].room)
    }

    // MARK: - B. 单双周 type

    func test_pku_single_double_week_单双周type() throws {
        let courses = try JwPekingParser(Self.pkuSingleDoubleWeek).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssertEqual(1, courses.first { $0.name == "大学物理" }!.type)   // "周一1~2节(单)"
        XCTAssertEqual(2, courses.first { $0.name == "化学实验" }!.type)   // "周四5~6节(双)"
    }

    // MARK: - C. pku_missing_fields 四行边界

    func test_pku_missing_fields_四行边界() throws {
        let courses = try JwPekingParser(Self.pkuMissingFields).generateCourseList()
        // 行1 tds.size<11 跳过；行2 时段空块跳过；
        // 行3 "1~16周 周二5~6节(实验楼201)" 两 token，room 走括号兜底 = "实验楼201"
        // 行4 状态"退课申请中"不含'未' → 正常解析，room=timeInfo[2]="教305"
        XCTAssertEqual(2, courses.count)
        let phys = courses.first { $0.name == "大学物理" }!
        XCTAssertEqual(2, phys.day)
        XCTAssertEqual(5, phys.startNode)
        XCTAssertEqual(6, phys.endNode)
        XCTAssertEqual("实验楼201", phys.room)
        let eng = courses.first { $0.name == "大学英语(二)" }!
        XCTAssertEqual(5, eng.day)
        XCTAssertEqual(7, eng.startNode)
        XCTAssertEqual(8, eng.endNode)
        XCTAssertEqual("教305", eng.room)
    }

    // MARK: - D. 空 tbody / 登录页

    func test_pku_empty_空tbody返回空() throws {
        XCTAssertEqual(0, try JwPekingParser(Self.pkuEmpty).generateCourseList().count)
    }

    func test_pku_login_无datagrid返回空不抛() throws {
        XCTAssertEqual(0, try JwPekingParser(Self.pkuLogin).generateCourseList().count)
    }

    func test_adversarial_pku_iaaa登录页不误产出() throws {
        XCTAssertEqual(0, try JwPekingParser(Self.pkuLogin).generateCourseList().count)
    }

    // MARK: - E. 多 ~ 边界（← Android substringAfter 语义，审计 issue 1/2 的回归锁）

    /// "3~~4节"：Android substringAfter('~') 取第一个 ~ 之后 = "~4节"，filter isDigit → "4"，
    /// endNode=4（旧 iOS components(separatedBy:"~")[1]="" → nil→兜底 endNode 会得 (3,3)，错）。
    func test_multi_tilde_node_range_matches_android_semantics() throws {
        let courses = try JwPekingParser(row(timeCell: "1~16周 周一3~~4节 教1")).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(3, courses[0].startNode)
        XCTAssertEqual(4, courses[0].endNode)
    }

    /// "1~2~16周"：Android substringAfter('~').substringBefore('周') → "2~16"，
    /// filter isDigit 跨第二个 ~ 拼接 → "216"，endWeek=216。
    func test_multi_tilde_week_range_matches_android_semantics() throws {
        let courses = try JwPekingParser(row(timeCell: "1~2~16周 周一3~4节 教1")).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(216, courses[0].endWeek)
    }

    /// 无 ~ 的节次串（"11节"）：Kotlin substringBefore/After 均返回整串 → start=end=11。
    func test_no_tilde_node_updates_both_start_and_end() throws {
        let courses = try JwPekingParser(row(timeCell: "1~16周 周一11节 教1")).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(11, courses[0].startNode)
        XCTAssertEqual(11, courses[0].endNode)
    }
}
