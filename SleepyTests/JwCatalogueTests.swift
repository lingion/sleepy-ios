// JwCatalogueTests.swift — ← Android v1.0.62 SchoolsJsonConsistencyTest.kt +
// SchoolSearchIndexTest.kt + JwImportReport 相关单测 (逐用例移植)
//
// B2 目录扩容后的契约锁:
//   - schools.json 从 348 条全量目录扩到 4140 条(其中 1478 条有可打开 URL)
//   - status 生命周期模型 (supported / pending / grad_* / unverified / legacy)
//   - stableKey / canImport / hasUrl 的判定口径
//   - 搜索索引的"子串命中 + 别名精确前置"语义
//   - 导入成功报告文本的字段与隐私边界

import XCTest
@testable import Sleepy

final class JwCatalogueTests: XCTestCase {

    // MARK: - 载入工具

    /// 走生产同源解析路径 + app bundle 的 schools.json
    private func loadSchools() throws -> [JwSchoolInfo] {
        let bundle = Bundle(for: JwImportViewModel.self)
        let url = Bundle.main.url(forResource: "schools", withExtension: "json")
            ?? bundle.url(forResource: "schools", withExtension: "json")
        let raw = try String(contentsOf: try XCTUnwrap(url, "schools.json 应存在"), encoding: .utf8)
        return JwImportViewModel.parseSchoolsJson(raw)
    }

    /// 有可打开 URL 的子集 —— ← Android loadSchools 的过滤结果
    private func loadImportableSchools() throws -> [JwSchoolInfo] {
        try loadSchools().filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func entryOf(_ list: [JwSchoolInfo], _ name: String) -> JwSchoolInfo? {
        list.first { $0.name == name }
    }

    // MARK: - 目录规模闸

    func testCatalogueSizePinnedToAndroidV1062() throws {
        // ← Android v1.0.62 tag 10adc247 assets/schools.json = 4140 条
        //   (v1.0.61 = 349; B2 对齐后 iOS resources/schools.json 与安卓逐条一致)
        let list = try loadSchools()
        XCTAssertEqual(4140, list.count)
        XCTAssertFalse(list[0].name.isEmpty)
    }

    func testOnlyEntriesWithUrlAreImportable() throws {
        // ← Android loadSchools: 只显示有 URL 的学校(避免用户看到大量不可用选项)
        let all = try loadSchools()
        let withUrl = try loadImportableSchools()
        XCTAssertEqual(1478, withUrl.count)
        XCTAssertLessThan(withUrl.count, all.count)
        // 无 URL 的条目一律不可导入
        for school in all where school.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertFalse(school.canImport, "\(school.name) 无 URL 不应可导入")
        }
    }

    func testStatusDistributionMatchesAndroid() throws {
        // ← Android v1.0.62 schools.json 状态分布:
        //   有 URL 1478 条 = supported 348 + grad_supported 2 + unverified 1128
        //   无 URL 2662 条 = pending 2361 + grad_pending 301
        let all = try loadSchools()
        let withUrl = try loadImportableSchools()
        let noUrl = all.filter { $0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        XCTAssertEqual(348, withUrl.filter { $0.isSupported && $0.status == JwSchoolInfo.STATUS_SUPPORTED }.count)
        XCTAssertEqual(2, withUrl.filter { $0.status == JwSchoolInfo.STATUS_GRAD_SUPPORTED }.count)
        XCTAssertEqual(1128, withUrl.filter { $0.isUnverified }.count)
        XCTAssertEqual(2361, noUrl.filter { $0.status == JwSchoolInfo.STATUS_PENDING }.count)
        XCTAssertEqual(301, noUrl.filter { $0.status == JwSchoolInfo.STATUS_GRAD_PENDING }.count)
    }

    func testEveryEntryCarriesCatalogIdAndUniqueStableKey() throws {
        // ← Android `catalogue keys are unique and expanded entries have explicit identities`
        let list = try loadSchools()
        XCTAssertEqual(list.count, Set(list.map { $0.stableKey }).count)
        XCTAssertTrue(list.allSatisfy { !$0.catalogId.isEmpty },
                      "扩容后的每条目录条目都应有显式 catalogId")
    }

    func testStatusValuesAreAllKnown() throws {
        // ← Android `status field if present is one of the known lifecycle values`
        let known: Set<String> = [
            JwSchoolInfo.STATUS_SUPPORTED, JwSchoolInfo.STATUS_PENDING,
            JwSchoolInfo.STATUS_GRAD_SUPPORTED, JwSchoolInfo.STATUS_GRAD_PENDING,
            JwSchoolInfo.STATUS_LEGACY, JwSchoolInfo.STATUS_UNVERIFIED,
            JwSchoolInfo.STATUS_GRAD_UNVERIFIED,
        ]
        let list = try loadSchools()
        for school in list {
            XCTAssertTrue(known.contains(school.status), "非法 status: \(school.name)=\(school.status)")
        }
    }

    func testSupportedOrUnverifiedEntriesAreImportable() throws {
        // ← Android `supported and unverified entries have valid import configuration`
        let list = try loadSchools()
        for school in list where school.isSupported || school.isUnverified {
            XCTAssertTrue(school.canImport,
                          "已支持/未验证条目必须可导入: \(school.name) status=\(school.status) url=\(school.url)")
        }
        for school in list where school.isPending {
            XCTAssertFalse(school.canImport, "待适配条目不得可导入: \(school.name)")
        }
    }

    func testDriftProneTypesHaveLiveEntries() throws {
        // ← Android `explicitly listed drift-prone types have live entries`
        let types = try loadSchools().compactMap { $0.type }
        for t in ["hnust", "cf", "pku", "bnuz"] {
            XCTAssertGreaterThanOrEqual(types.filter { $0 == t }.count, 1, "type=\(t) 应至少 1 所学校")
        }
    }

    // MARK: - normalizeStatus

    func testNormalizeStatusFailClosed() {
        // ← Android normalizeStatus: null/"" → supported; grad_* / unverified / legacy 原样;
        //   未知值 → pending (fail-closed)
        XCTAssertEqual(JwSchoolInfo.STATUS_SUPPORTED, JwSchoolInfo.normalizeStatus(nil))
        XCTAssertEqual(JwSchoolInfo.STATUS_SUPPORTED, JwSchoolInfo.normalizeStatus(""))
        XCTAssertEqual(JwSchoolInfo.STATUS_SUPPORTED, JwSchoolInfo.normalizeStatus("supported"))
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_SUPPORTED, JwSchoolInfo.normalizeStatus("grad_supported"))
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_PENDING, JwSchoolInfo.normalizeStatus("grad_pending"))
        XCTAssertEqual(JwSchoolInfo.STATUS_UNVERIFIED, JwSchoolInfo.normalizeStatus("unverified"))
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_UNVERIFIED, JwSchoolInfo.normalizeStatus("grad_unverified"))
        XCTAssertEqual(JwSchoolInfo.STATUS_LEGACY, JwSchoolInfo.normalizeStatus("legacy"))
        XCTAssertEqual(JwSchoolInfo.STATUS_PENDING, JwSchoolInfo.normalizeStatus("wat"))
        XCTAssertEqual(JwSchoolInfo.STATUS_PENDING, JwSchoolInfo.normalizeStatus("SUPPORTED"))
    }

    func testNormalizeStatusInParserPipeline() {
        // ← Android JwNewSchoolsTest `parseSchoolsJson reads explicit status values`
        let mini = """
            [
              {"sortKey": "Z", "name": "测试A", "url": "https://a.edu/", "type": "zf_new", "aliases": [], "sortKeyFull": "a"},
              {"sortKey": "Z", "name": "测试B", "url": "https://b.edu/", "type": "qz", "aliases": [], "sortKeyFull": "b", "status": "pending"},
              {"sortKey": "Z", "name": "测试C", "url": "https://c.edu/", "type": "urp", "aliases": [], "sortKeyFull": "c", "status": "legacy"},
              {"sortKey": "Z", "name": "测试D", "url": "https://d.edu/", "type": "wisedu", "aliases": [], "sortKeyFull": "d", "status": "grad_supported"},
              {"sortKey": "Z", "name": "测试E", "url": "https://e.edu/", "type": "urp_new", "aliases": [], "sortKeyFull": "e", "status": "grad_pending"}
            ]
            """
        let parsed = JwImportViewModel.parseSchoolsJson(mini)
        XCTAssertEqual(5, parsed.count)
        XCTAssertEqual(JwSchoolInfo.STATUS_SUPPORTED, parsed[0].status)
        XCTAssertEqual(JwSchoolInfo.STATUS_PENDING, parsed[1].status)
        XCTAssertEqual(JwSchoolInfo.STATUS_LEGACY, parsed[2].status)
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_SUPPORTED, parsed[3].status)
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_PENDING, parsed[4].status)
        XCTAssertTrue(parsed[0].isSupported)
        XCTAssertFalse(parsed[1].isSupported)
        XCTAssertTrue(parsed[3].isSupported)
        XCTAssertTrue(parsed[3].isGrad)
        XCTAssertTrue(parsed[4].isGrad)
        XCTAssertFalse(parsed[0].isGrad)
    }

    // MARK: - stableKey / hasUrl / canImport

    func testStableKeyPrefersCatalogId() {
        // ← Android stableKey = catalogId.ifBlank { "${sortKey}_${name}" }
        let withId = JwSchoolInfo(sortKey: "A", name: "甲大学", catalogId: "A_甲大学")
        XCTAssertEqual("A_甲大学", withId.stableKey)
        let withoutId = JwSchoolInfo(sortKey: "A", name: "甲大学")
        XCTAssertEqual("A_甲大学", withoutId.stableKey)
        let blankId = JwSchoolInfo(sortKey: "A", name: "甲大学", catalogId: "   ")
        XCTAssertEqual("A_甲大学", blankId.stableKey)
    }

    func testHasUrlRejectsNonHttpAndUserInfo() {
        // ← Android hasUrl: http/https + host 非空 + 无 userInfo
        func has(_ url: String) -> Bool {
            JwSchoolInfo(sortKey: "A", name: "甲", url: url).hasUrl
        }
        XCTAssertTrue(has("https://a.edu.cn/jw/"))
        XCTAssertTrue(has("http://a.edu.cn"))
        XCTAssertFalse(has(""))
        XCTAssertFalse(has("   "))
        XCTAssertFalse(has("ftp://a.edu.cn"))
        XCTAssertFalse(has("a.edu.cn"))
        XCTAssertFalse(has("https:///jw"))          // host 空
        XCTAssertFalse(has("https://user:pw@a.edu.cn"))  // 带凭据
    }

    func testCanImportCombinesSupportAndParserAndUrl() {
        // ← Android canImport = (isSupported || (isUnverified && registry.supports(type))) && hasUrl
        let supported = JwSchoolInfo(sortKey: "A", name: "甲", url: "https://a.edu.cn/",
                                     type: "zf_new", status: JwSchoolInfo.STATUS_SUPPORTED)
        XCTAssertTrue(supported.canImport)

        let unverifiedRoutable = JwSchoolInfo(sortKey: "A", name: "甲", url: "https://a.edu.cn/",
                                              type: "zf_new", status: JwSchoolInfo.STATUS_UNVERIFIED)
        XCTAssertTrue(unverifiedRoutable.canImport)

        let unverifiedNoParser = JwSchoolInfo(sortKey: "A", name: "甲", url: "https://a.edu.cn/",
                                               type: "not_a_protocol", status: JwSchoolInfo.STATUS_UNVERIFIED)
        XCTAssertFalse(unverifiedNoParser.canImport, "未验证 + 无 parser → 不可导入")

        let pending = JwSchoolInfo(sortKey: "A", name: "甲", url: "https://a.edu.cn/",
                                   type: "zf_new", status: JwSchoolInfo.STATUS_PENDING)
        XCTAssertFalse(pending.canImport, "待适配不得可导入")

        let noUrl = JwSchoolInfo(sortKey: "A", name: "甲", url: "",
                                 type: "zf_new", status: JwSchoolInfo.STATUS_SUPPORTED)
        XCTAssertFalse(noUrl.canImport)
    }

    func testParserRegistrySupportsKnownType() {
        XCTAssertTrue(JwParserRegistry.supports("zf_new"))
        XCTAssertFalse(JwParserRegistry.supports("definitely_not_a_protocol"))
        XCTAssertFalse(JwParserRegistry.supports(nil))
    }

    // MARK: - 搜索索引 (← Android SchoolSearchIndexTest.kt)

    private func searchFixture() -> [JwSchoolInfo] {
        [
            JwSchoolInfo(sortKey: "A", name: "Alpha University", url: "https://a.edu/",
                         type: "zf_new", aliases: ["alpha", "a.edu"]),
            JwSchoolInfo(sortKey: "B", name: "Beta Institute", url: "https://b.edu/",
                         type: "qz", aliases: ["beta"]),
        ]
    }

    func testBlankQueryReturnsWholeCatalogue() {
        // ← Android `assertEquals(schools, index.search(" "))`
        let schools = searchFixture()
        let index = SchoolSearchIndex(schools)
        XCTAssertEqual(schools, index.search(" "))
        XCTAssertEqual(schools, index.search(""))
    }

    func testSubstringMatchOnTerm() {
        // 过滤用 `q in term` = 子串包含
        let index = SchoolSearchIndex(searchFixture())
        XCTAssertEqual(["Alpha University"], index.search("Alpha").map { $0.name })
        XCTAssertEqual(["Beta Institute"], index.search("Bet").map { $0.name })
        XCTAssertEqual([], index.search("Zeta"))
    }

    func testExactAliasMatchSortsFirst() {
        // ← Android 排序键 `q in it.aliases` (Set → 精确相等), 过滤却是子串 → 两者语义不同
        let schools = [
            JwSchoolInfo(sortKey: "A", name: "Alpha University", url: "https://a.edu/", aliases: ["alpha"]),
            JwSchoolInfo(sortKey: "Z", name: "Zeta University", url: "https://z.edu/", aliases: ["alpha2"]),
        ]
        let index = SchoolSearchIndex(schools)
        // "alpha" 精确命中 Alpha 的别名 → 前置; "alpha2" 只子串命中 Zeta
        XCTAssertEqual("Alpha University", index.search("alpha").first?.name)
        XCTAssertEqual(["Alpha University", "Zeta University"], index.search("alpha").map { $0.name })
        XCTAssertEqual(["Zeta University"], index.search("alpha2").map { $0.name })
    }

    func testSearchMatchesPinyinAliasOfRealEntry() throws {
        // 真实目录条目: 用一个带别名的学校验证"中文名 / 拼音缩写 / 别名"三种入口
        let list = try loadSchools()
        let index = SchoolSearchIndex(list)
        let hit = try XCTUnwrap(entryOf(list, "燕山大学"))
        XCTAssertTrue(index.search("燕山大学").contains(hit))
        for alias in hit.aliases {
            XCTAssertTrue(index.search(alias).contains(hit), "别名 \(alias) 应命中")
        }
    }

    // MARK: - 域名匹配 (← Android SchoolDomainMatch)

    func testParsedRejectsNonHttpAndUserInfo() {
        XCTAssertNil(SchoolDomainMatch.parsed("ftp://a.edu/"))
        XCTAssertNil(SchoolDomainMatch.parsed("a.edu"))
        XCTAssertNil(SchoolDomainMatch.parsed("https://user:pw@a.edu/"))
        let ok = SchoolDomainMatch.parsed("https://a.edu/jw/entry?x=1")
        XCTAssertEqual("https", ok?.scheme)
        XCTAssertEqual("a.edu", ok?.host)
        XCTAssertEqual("/jw/entry", ok?.path)
        XCTAssertEqual("x=1", ok?.query)
        XCTAssertEqual(443, ok?.effectivePort)
    }

    func testSameEntryTreatsEmptyPathAsSlash() {
        // ← Android sameEntry: 路径缺省都算 "/"
        let a = SchoolDomainMatch.parsed("https://a.edu")
        let b = SchoolDomainMatch.parsed("https://a.edu/")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertTrue(SchoolDomainMatch.sameEntry(a!, b!))
        let c = SchoolDomainMatch.parsed("https://a.edu/other")
        XCTAssertFalse(SchoolDomainMatch.sameEntry(a!, c!))
    }

    func testMatchSchoolOnlyRewritesSupportedUniqueEntries() {
        let catalog = [
            JwSchoolInfo(sortKey: "A", name: "甲大学", url: "https://jw.a.edu/",
                         type: "zf_new", status: JwSchoolInfo.STATUS_SUPPORTED),
            JwSchoolInfo(sortKey: "A", name: "待适配大学", url: "https://jw.b.edu/",
                         type: "zf_new", status: JwSchoolInfo.STATUS_PENDING),
        ]
        // 同注册域 + 已支持 → 命中
        XCTAssertEqual("甲大学", SchoolDomainMatch.matchSchool("https://jw.a.edu/", catalog)?.name)
        // 待适配条目永不自动改写用户输入的 URL
        XCTAssertNil(SchoolDomainMatch.matchSchool("https://jw.b.edu/", catalog))
        // 未知域 → nil
        XCTAssertNil(SchoolDomainMatch.matchSchool("https://unknown.example/", catalog))
    }

    func testSelectionsForUrlKeepsPendingExactEntry() {
        // ← Android selectionsForUrl: 精确已知的 URL 保留其状态(包括 pending)
        let catalog = [
            JwSchoolInfo(sortKey: "A", name: "待适配大学", url: "https://jw.b.edu/",
                         type: "zf_new", status: JwSchoolInfo.STATUS_PENDING),
        ]
        let sels = SchoolDomainMatch.selectionsForUrl("https://jw.b.edu/", catalog, protocolType: nil, customName: "x")
        XCTAssertEqual(1, sels.count)
        XCTAssertEqual(JwSchoolInfo.STATUS_PENDING, sels[0].status)
    }

    func testSelectionsForUrlFallsBackToCustomEntry() {
        let sels = SchoolDomainMatch.selectionsForUrl("https://unknown.example/", [],
                                                      protocolType: nil, customName: "我的学校")
        XCTAssertEqual(1, sels.count)
        XCTAssertEqual("我的学校", sels[0].name)
        XCTAssertEqual("https://unknown.example/", sels[0].url)
    }
}
