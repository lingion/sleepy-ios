// SchoolCityIndexTests.swift — ← SchoolCityIndexTest.kt (纯逻辑部分)
// 资产文件依赖的用例(schools.json/school_cities.json 全量对账)依赖 Android 侧
// sleepy.test.root 机制, iOS 测试 target 未挂载对应目录, 未移植。
// normalizeCity 后缀语义 + parse 抛错语义为 v1.0.61 对齐修复的回归点。

import XCTest
@testable import Sleepy

final class SchoolCityIndexTests: XCTestCase {

    private func school(_ name: String, _ city: String, key: String = "",
                        status: String = JwSchoolInfo.STATUS_SUPPORTED) -> JwSchoolInfo {
        JwSchoolInfo(sortKey: "A", name: name, status: status,
                     sortKeyFull: key.isEmpty ? name : key, cities: [city])
    }

    // MARK: - normalizeCity: 只剥单个结尾"市"(Android removeSuffix 语义)

    func testNormalizeCityStripsOnlyOneTrailingSuffix() {
        XCTAssertEqual(SchoolCityIndex.normalizeCity("北京市"), "北京")
        XCTAssertEqual(SchoolCityIndex.normalizeCity("北京"), "北京")
        XCTAssertEqual(SchoolCityIndex.normalizeCity("  合肥市 \n"), "合肥")
        // 回归: 中间/开头的"市"不能被吃掉 (replacingOccurrences 全局替换的旧 bug)
        XCTAssertEqual(SchoolCityIndex.normalizeCity("沙市市"), "沙市")
        XCTAssertEqual(SchoolCityIndex.normalizeCity("市北区"), "市北区")
        XCTAssertEqual(SchoolCityIndex.normalizeCity("市口市"), "市口")
    }

    // MARK: - city suffix and whitespace are normalized without substring matching

    func testCitySuffixAndWhitespaceNormalized() {
        let schools = [school("合肥学校", "合肥市"), school("肥城学校", "肥城市")]
        XCTAssertEqual(SchoolCityIndex.schoolsInCity(schools, city: " 合肥 ").map(\.name), ["合肥学校"])
        XCTAssertTrue(SchoolCityIndex.schoolsInCity(schools, city: "肥").isEmpty)
        XCTAssertTrue(SchoolCityIndex.schoolsInCity(schools, city: "安徽省").isEmpty)
        XCTAssertTrue(SchoolCityIndex.schoolsInCity(schools, city: " ").isEmpty)
    }

    // MARK: - recommendations prefer supported entries then use pinyin without changing input order

    func testRecommendationsPreferSupportedThenPinyin() throws {
        let pending = school("待适配学校", "合肥市", key: "a", status: JwSchoolInfo.STATUS_PENDING)
        let beta = school("乙校", "合肥市", key: "b")
        let alpha = school("甲校", "合肥市", key: "a")
        let input = [pending, beta, alpha]
        XCTAssertEqual(SchoolCityIndex.schoolsInCity(input, city: "合肥市"), [alpha, beta, pending])
        XCTAssertEqual(input, [pending, beta, alpha]) // 输入顺序不被修改
    }

    // MARK: - multi city schools appear once and unknown metadata is not guessed from name

    func testMultiCitySchoolsAppearOnce() {
        var multi = school("多校区大学", "北京市")
        multi.cities = ["北京市", "保定市"]
        let unknown = JwSchoolInfo(sortKey: "B", name: "保定未知学校")
        let matched = SchoolCityIndex.schoolsInCity([multi, multi, unknown], city: "保定市")
        XCTAssertEqual(matched, [multi])
    }

    // MARK: - metadata is ignored by index parser and empty city strings are excluded

    func testParseIgnoresMetadataAndFiltersBlankCities() throws {
        let result = try SchoolCityIndex.parse(
            "{\"_source\":\"official\",\"schools\":{\"学校\":[\"\", \"合肥市\"]}}")
        XCTAssertEqual(result, ["学校": ["合肥市"]])
    }

    // MARK: - parse 错误语义: 坏输入必须抛错, 不能静默返回空表 (对齐 Android JSONException)

    func testParseThrowsOnMalformedJson() {
        XCTAssertThrowsError(try SchoolCityIndex.parse("{not json"))
    }

    func testParseThrowsOnMissingSchoolsKey() {
        XCTAssertThrowsError(try SchoolCityIndex.parse("{\"_source\":\"official\"}"))
    }

    func testParseThrowsOnNonObjectRoot() {
        XCTAssertThrowsError(try SchoolCityIndex.parse("[1,2,3]"))
    }

    func testParseThrowsOnNonArrayCityValue() {
        XCTAssertThrowsError(try SchoolCityIndex.parse("{\"schools\":{\"学校\":\"合肥\"}}"))
    }

    func testParseThrowsOnNonStringCityElement() {
        XCTAssertThrowsError(try SchoolCityIndex.parse("{\"schools\":{\"学校\":[123]}}"))
    }
}
