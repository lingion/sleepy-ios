import XCTest
@testable import Sleepy

final class JwClassicEamsRegressionTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "html") throws -> String {
        let bundle = Bundle(for: JwClassicEamsRegressionTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "resources/classic_eams")
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "classic_eams")
            ?? bundle.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testNbccActionParsesExactNamesSparseWeeksAndLinearIndex() throws {
        let courses = try JwClassicEamsParser(fixture("nbcc-course-table-action")).generateCourseList()
        XCTAssertEqual(courses.count, 21)
        let sports = courses.filter { $0.name == "体育健康-1(020D01G35)" }
        XCTAssertEqual(sports.count, 12)
        XCTAssertEqual(sports.first?.teacher, "赵老师/钱老师")
        XCTAssertEqual(sports.first?.day, 4)
        XCTAssertEqual(sports.first?.startNode, 3)
        XCTAssertEqual(sports.first?.endNode, 4)
        XCTAssertEqual(sports.map(\.startWeek), [5,6,7,8,10,11,12,13,14,15,16,17])
        let math = courses.filter { $0.name == "高等数学(下)(032A04C03)" }
        XCTAssertEqual(math.map(\.startWeek), [2,4,6,8])
        XCTAssertEqual(math.first?.day, 4)
        XCTAssertEqual(math.first?.startNode, 7)
    }

    func testNankaiActionUsesExistingClassicParser() throws {
        let html = try fixture("nankai-course-table-action")
        let result = JwParseDispatch.parse(html, JwProtocol.TYPE_CLASSIC_EAMS)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.courses.count, 23)
        XCTAssertEqual(result.courses.first?.name, "数学分析A(100101G1)")
        XCTAssertEqual(result.courses.first?.teacher, "李老师/王老师")
        let policy = try XCTUnwrap(result.courses.first { $0.name == "形势与政策(100303G3)" })
        XCTAssertEqual(policy.day, 4)
        XCTAssertEqual(policy.startNode, 7)
        XCTAssertEqual(policy.startWeek, 20)
    }

    func testEntryLoginAndMobileShellsNeverBecomeCourses() throws {
        for name in ["nankai-entry-page", "nankai-iam-login-page", "nbcc-entry-page",
                     "nbcc-login-page", "nbcc-empty-shell", "nbcc-mobile-spa-shell"] {
            XCTAssertTrue(try JwClassicEamsParser(fixture(name)).generateCourseList().isEmpty, name)
        }
        XCTAssertTrue(try JwClassicEamsParser(fixture("nbcc-shuwei-mixed", ext: "json")).generateCourseList().isEmpty)
    }

    func testDesktopUAUsesExactNbccHostWithoutPromotingStatus() {
        let school = JwSchoolInfo(sortKey: "N", name: "宁波城市职业技术学院",
                                  url: "https://webvpn.nbcc.edu.cn/login", type: "classic_eams",
                                  status: "unverified", enableFetch: false)
        XCTAssertTrue(JwClassicEamsFetch.initialDesktopUa(school))
        XCTAssertTrue(school.isUnverified)
        XCTAssertFalse(school.enableFetch)
        var other = school
        for url in ["https://webvpn.nbcc.edu.cn.evil.example/login", "https://jwgl.webvpn.nbcc.cn/eams/", "https://eamis.nankai.edu.cn/", "file://webvpn.nbcc.edu.cn/login"] {
            other.url = url
            XCTAssertFalse(JwClassicEamsFetch.initialDesktopUa(other), url)
        }
        other.url = school.url
        other.type = "shuwei_json"
        XCTAssertFalse(JwClassicEamsFetch.initialDesktopUa(other))
    }

    func testFetchUsesSourceRegexConstantsInScriptAndRealEntryScopes() throws {
        for pattern in [JwClassicEamsFetch.idsPattern, JwClassicEamsFetch.semesterPattern] {
            XCTAssertTrue(JwClassicEamsFetch.js.contains("/" + pattern + "/"))
            let regex = try NSRegularExpression(pattern: pattern)
            for name in ["nbcc-entry-page", "nankai-entry-page"] {
                let html = try fixture(name)
                let anchor = try XCTUnwrap(html.range(of: "courseTableForStd", options: .caseInsensitive))
                let scope = String(html[anchor.lowerBound...])
                XCTAssertNotNil(regex.firstMatch(in: scope, range: NSRange(scope.startIndex..., in: scope)), name)
            }
        }
        XCTAssertTrue(JwClassicEamsFetch.js.contains("slice(0,3)"))
        XCTAssertTrue(JwClassicEamsFetch.js.contains("credentials:'same-origin'"))
    }
}
