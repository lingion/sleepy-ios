// JwWakeUpCompatParserTests.swift — ← JwWakeUpCompatParserTest.kt (逐用例) + 漂移回归锁
//
// WakeUp 协议族兼容解析器测试: chaoxing schema / cumtb 时间换算 + 未知占位 /
// south_soft 单双周 / jz json + jz html / kingo TaskActivity 网格 / xju 花括号块 +
// registry 兜底路由 / suda 标签 + rowspan endNode / shuwei 周次区间。
//
// 尾部「回归锁」用例对应本轮修掉的 iOS 漂移:
//  - xju 第二表选择器 #contentParent_dgData (2026-09-17 Gwork 报修形态)
//  - suda 回退选择器 #MainWork_DataGrid1
//  - marked table 无 data-* 属性时回退单元格文本(attr 返回 "" ≠ nil)
//  - 混合/null JSON 数组不得整体杀掉 JSON 通路
//  - chaoxing xq 为数字时照常出行(org.json optString 强转语义)

import XCTest
@testable import Sleepy

final class JwWakeUpCompatParserTests: XCTestCase {

    // MARK: - mirror of JwWakeUpCompatParserTest.kt

    func testLegacyChaoxingUsesKckbDataSchema() throws {
        let source = """
            {"data":{"kckbData":[{"kcmc":"<b>高等数学</b>","xq":"2","djc":3,"tmc":"张老师","croommc":"教一-101","zc":"1-16,18","zctype":"0"}]}}
        """
        let courses = try JwChaoxingLegacyParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].name, "高等数学")
        XCTAssertEqual(courses[0].day, 2)
        XCTAssertEqual(courses[0].startNode, 3)
        XCTAssertEqual(courses[0].endWeek, 16)
        XCTAssertEqual(courses[1].startWeek, 18)
    }

    func testCumtbJoinsLessonNamesAndConvertsTime() throws {
        let source = """
            {"result":{"lessonList":[{"id":7,"courseName":"数据库"}],"scheduleList":[{"lessonId":7,"personName":"李老师","weekday":4,"weekIndex":6,"startTime":800,"endTime":945,"room":{"nameZh":"信科-201"}}]}}
        """
        let courses = try JwCumtbParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        let c = try XCTUnwrap(courses.first)
        XCTAssertEqual(c.name, "数据库")
        XCTAssertEqual(c.day, 4)
        XCTAssertEqual(c.startNode, 1)
        XCTAssertEqual(c.endNode, 2)
        XCTAssertEqual(c.room, "信科-201")
        XCTAssertEqual(c.startWeek, 6)
    }

    func testCumtbUnknownLessonFallsBackToPlaceholder() throws {
        // WakeUp oo000o.java:45 — lessonList 缺失的 lessonId → "未知", 行不丢
        let source = """
            {"result":{"lessonList":[],"scheduleList":[{"lessonId":99,"personName":"王老师","weekday":2,"weekIndex":3,"startTime":1400,"endTime":1535,"room":{"nameZh":"教1-102"}}]}}
        """
        let courses = try JwCumtbParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        let c = try XCTUnwrap(courses.first)
        XCTAssertEqual(c.name, "未知")
        XCTAssertEqual(c.day, 2)
        XCTAssertEqual(c.startNode, 5)
        XCTAssertEqual(c.room, "教1-102")
    }

    func testSouthSoftParsesXqKeyAndOddEvenTokens() throws {
        let source = """
            [{"KCWZSM":"线性代数","KEY":"xq3_jc2","SKSJ":"[数学][周1-16单][张老师][A-101][第2-3节]"}]
        """
        let courses = try JwSouthSoftParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        let c = try XCTUnwrap(courses.first)
        XCTAssertEqual(c.name, "线性代数")
        XCTAssertEqual(c.day, 3)
        XCTAssertEqual(c.startNode, 2)
        XCTAssertEqual(c.endNode, 3)
        XCTAssertEqual(c.type, 1)
        XCTAssertEqual(c.endWeek, 16)
    }

    func testJzJsonArrayUsesHandCourseInfoSchema() throws {
        let source = """
            [{"kcmc":"数据结构","xqj":3,"jsxm":"钱老师","skdd":"教2-301","djj":5,"dsz":6,"qmz":"1-8;10-16","bjmc":"计科21","xkkh":"(2025-2026-1)-","lx":1,"mz":2,"qz":0,"rwlx":1}]
        """
        let courses = try JwJzParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].name, "数据结构")
        XCTAssertEqual(courses[0].day, 3)
        XCTAssertEqual(courses[0].startNode, 5)
        XCTAssertEqual(courses[0].room, "教2-301")
        XCTAssertEqual(courses[0].teacher, "钱老师")
        XCTAssertEqual(courses[0].startWeek, 1)
        XCTAssertEqual(courses[0].endWeek, 8)
        XCTAssertEqual(courses[1].startWeek, 10)
        XCTAssertEqual(courses[1].endWeek, 16)
    }

    func testJzHtmlCourseFormTableBrSplit() throws {
        let source = """
            <html><body><table id="CourseFormTable">
            <tr><td>&nbsp;</td><td style="text-align:center">星期一</td></tr>
            <tr><td style="text-align:center">第5节</td>
            <td>数据结构<br>1-16单,18<br>钱老师<br>第5-6节<br>教2-301</td></tr>
            </table></body></html>
        """
        let courses = try JwJzParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        XCTAssertEqual(courses[0].name, "数据结构")
        XCTAssertEqual(courses[0].day, 2)
        XCTAssertEqual(courses[0].type, 1)
        XCTAssertEqual(courses[0].room, "教2-301")
        XCTAssertEqual(courses[0].teacher, "钱老师")
    }

    func testKingoTaskActivityGridUsesIndexTimesUnitCount() throws {
        let source = """
            <html><body><script>
            var activity = null;
            var courseName = '高等代数';
            var actTeachers = new Array();
            actTeachers.push({'name':'孙老师'});
            activity = new TaskActivity('高等代数','孙老师','博学楼A-302','101010000000000000000000000000000000000000000000');
            index = 3 * unitCount + 2;
            activity.index = index;
            table0.marshalTable();
            </script></body></html>
        """
        let courses = try JwKingoParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        let c = try XCTUnwrap(courses.first)
        XCTAssertEqual(c.name, "高等代数")
        // 跨仓 4 源一致: index 首因子 0-based, day=D+1
        XCTAssertEqual(c.day, 4)
        XCTAssertEqual(c.startNode, 3)
        XCTAssertEqual(c.room, "博学楼A-302")
        XCTAssertEqual(c.teacher, "孙老师")
        XCTAssertEqual(c.startWeek, 1)
        XCTAssertEqual(c.endWeek, 5)
        XCTAssertEqual(c.type, 1)
    }

    func testXjuDgDataBraceBlocksWithWeekParity() throws {
        let source = """
            <html><body><table id="ctl00_contentParent_dgData">
            <tr><th>节次</th><th>星期一</th><th>星期二</th></tr>
            <tr><td align="center">第1-2节</td>
            <td>{大学物理(1-16周单)[教师:李老师,地点:物理楼-1]}</td><td>&nbsp;</td></tr>
            <tr><td align="center">第3-4节</td><td>&nbsp;</td>
            <td>{有机化学(2-15周双)[教师:周老师,地点:化学楼-2]}</td></tr>
            </table></body></html>
        """
        let courses = try JwXjuParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        let physics = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(physics.day, 1)
        XCTAssertEqual(physics.startNode, 1)
        XCTAssertEqual(physics.teacher, "李老师")
        XCTAssertEqual(physics.type, 1)
        let chem = try XCTUnwrap(courses.first { $0.name == "有机化学" })
        XCTAssertEqual(chem.room, "化学楼-2")
        XCTAssertEqual(chem.day, 2)
        XCTAssertEqual(chem.type, 2)
    }

    func testSudaGridRowsUseCourseTeacherLabels() throws {
        let source = """
            <html><body><table id="MainWork_DataGrid1">
            <tr align="center"><td>星期一</td><td>星期二</td></tr>
            <tr><td>高等数学<br>课程:高等数学<br>(张老师)<br>第1-16周<br>博远楼-101</td><td>&nbsp;</td></tr>
            <tr><td>&nbsp;</td><td>大学英语<br>课程:大学英语<br>(刘老师)<br>第1-16周双<br>博远楼-202</td></tr>
            </table></body></html>
        """
        let courses = try JwSudaParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(math.day, 1)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 16)
        XCTAssertEqual(math.teacher, "张老师")
        XCTAssertEqual(math.room, "博远楼-101")
        let english = try XCTUnwrap(courses.first { $0.name == "大学英语" })
        XCTAssertEqual(english.day, 2)
        XCTAssertEqual(english.type, 2)
    }

    func testSudaRowspanCellExtendsEndNode() throws {
        // WakeUp dex L00e9 rowspan 折叠: 连堂课单元格占 2 节
        let source = """
            <html><body><table id="MainWork_DataGrid1">
            <tr align="center"><td>星期一</td><td>星期二</td></tr>
            <tr><td>高等数学<br>课程:高等数学<br>(张老师)<br>第1-16周<br>博远楼-101</td><td rowspan="2">数据结构<br>课程:数据结构<br>(钱老师)<br>第1-16周<br>教2-301</td></tr>
            <tr><td>&nbsp;</td></tr>
            </table></body></html>
        """
        let courses = try JwSudaParser(source).generateCourseList()
        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" })
        XCTAssertEqual(ds.day, 2)
        XCTAssertEqual(ds.startNode, 1)
        XCTAssertEqual(ds.endNode, 2)
    }

    func testShuweiActivitiesPreserveOddEvenRanges() throws {
        let source = """
            {"activities":[{"courseName":"编译原理","weekday":5,"startSection":7,"endSection":8,"weeksStr":"1-15单,2-16双","room":"C-201","teacher":"王老师"}]}
        """
        let courses = try JwShuweiParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].type, 1)
        XCTAssertEqual(courses[0].endWeek, 15)
        XCTAssertEqual(courses[1].type, 2)
        XCTAssertEqual(courses[1].endWeek, 16)
    }

    func testXjuHtmlRoutesThroughRegistryToXjuParser() throws {
        // 自定义 URL 场景: declaredType=null → selectBest 全候选裁决落到 JwXjuParser
        // (sundayFirst: 课程在"星期一"列 → day=1)
        let source = """
            <html><head><title>学生课表查询</title></head><body>
            <table id="ctl00_contentParent_dgData" border="1">
            <tr><th>节次</th><th>星期日</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th></tr>
            <tr><td align="center">1</td><td></td><td>｛高等数学(1-16周)[教师：张三,地点：X101]｝</td><td></td><td></td><td></td><td></td><td></td></tr>
            </table></body></html>
        """
        let (courses, attempts) = JwParserRegistry.selectBest(source, declaredType: nil)
        XCTAssertFalse(courses.isEmpty, "应解析出课程, 实际 attempts=\(attempts.map { ($0.parserName, $0.courseCount) })")
        let best = attempts.filter { $0.courseCount == courses.count }
            .max(by: { $0.confidence < $1.confidence })
        XCTAssertEqual(best?.type, JwProtocol.TYPE_XJU_POST)
        XCTAssertEqual(courses[0].name, "高等数学")
        XCTAssertEqual(courses[0].day, 1)
    }

    // MARK: - 漂移回归锁 (本轮修复点)

    /// 回归锁#1: XJU 真实 Gwork 形态 B 表 id 无 ctl00_ 前缀 → 第二选择器必须命中
    func testXjuFormBWithoutCtl00PrefixSelector() throws {
        let source = """
            <html><body><table id="contentParent_dgData">
            <tr><th>时间</th><th>节次</th><th>星期一</th><th>星期二</th></tr>
            <tr><td rowspan="2" align="center">上午</td><td align="center">一</td>
            <td>马克思主义基本原理｛1-16周[教师:孙冬璞,地点:教三-301]｝</td><td>&nbsp;</td></tr>
            <tr><td align="center">二</td><td>｛高等数学(1-16周)[教师:张三,地点:X101]｝</td><td>&nbsp;</td></tr>
            </table></body></html>
        """
        let courses = try JwXjuParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty, "#contentParent_dgData(无 ctl00_ 前缀)必须被第二选择器接住(2026-09-17 报修案例)")
        XCTAssertTrue(courses.contains { $0.name == "马克思主义基本原理" })
    }

    /// 回归锁#2: suda DataGrid1 缺失时回退 MainWork_DataGrid1 (Android 测试 171/195 同款输入)
    func testSudaMainWorkFallbackSelector() throws {
        let source = """
            <html><body><table id="MainWork_DataGrid1">
            <tr><td align="center">1</td><td>课程:线性代数<br>(王老师)<br>第1-8周<br>A101</td></tr>
            </table></body></html>
        """
        let courses = try JwSudaParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty, "仅有 #MainWork_DataGrid1 的页面不得返回空")
        XCTAssertEqual(courses.first?.name, "线性代数")
    }

    /// 回归锁#3: marked table 无 data-* 属性 → room/teacher 回退单元格文本(attr "" ≠ nil)
    func testMarkedTableFallsBackToCellTextWithoutDataAttrs() throws {
        // 触发 marked-table 通路: kingosoft marker + 无 data-* 的行; day/node 走文本抽取
        let source = """
            <html><body>kingosoft<table>
            <tr><td>流体力学</td><td>星期三 第5节</td><td>孙老师</td><td>博学楼A-2</td></tr>
            </table></body></html>
        """
        let courses = try JwKingoParser(source).generateCourseList()
        let c = try XCTUnwrap(courses.first { $0.name == "流体力学" },
                              "marked table 行应产出课程, 实际 names=\(courses.map { $0.name })")
        XCTAssertEqual(c.day, 3)
        XCTAssertEqual(c.startNode, 5)
        XCTAssertEqual(c.teacher, "孙老师", "data-teacher 缺失(\"\")时须回退第 3 列文本")
        XCTAssertEqual(c.room, "博学楼A-2", "data-room 缺失(\"\")时须回退第 4 列文本")
    }

    /// 回归锁#4: chaoxing xq 数字型(非字符串)照常出行 — org.json optString 强转语义
    func testChaoxingNumericXqNotDropped() throws {
        let source = """
            {"data":{"kckbData":[{"kcmc":"大学物理","xq":3,"djc":2,"tmc":"赵老师","croommc":"物楼-1","zc":"1-8","zctype":0}]}}
        """
        let courses = try JwChaoxingLegacyParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 1, "\"xq\":3 数字不得整行丢弃")
        XCTAssertEqual(courses[0].day, 3)
    }

    /// 回归锁#5: 顶层数组含 null/原始值元素不得杀掉整个 JSON 通路
    func testMixedJsonArrayDoesNotKillJsonRoute() throws {
        let source = """
            [null,{"kcmc":"高等数学","xqj":2,"djj":1,"dsz":0,"qmz":"1-8","skdd":"一教101","jsxm":"李老师"},"junk"]
        """
        let courses = try JwJzParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty, "混合数组里的合法对象行必须解析成功(对齐 optJSONObject(i) ?: continue)")
        XCTAssertEqual(courses.first?.name, "高等数学")
    }

    /// 回归锁#6: kingo teacher 正则锚定 'name' 键 — 非 name 键值对不得吞进 teacher
    func testKingoTeacherOnlyFromNameKey() throws {
        let source = """
            <html><body><script>
            var activity = null;
            actTeachers.push({'teacher':'张三','course':'高数'});
            activity = new TaskActivity('高数','','博学楼B-1','100000000000000000000000000000000000000000000000');
            index = 0 * unitCount + 0;
            table0.marshalTable();
            </script></body></html>
        """
        let courses = try JwKingoParser(source).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        XCTAssertNotEqual(courses[0].teacher, "张三,高数", "'teacher'/'course' 键不是锚定的 'name' 键, Android 语义不采")
    }

    /// 回归锁#7: XJU 周次 token 分隔符含全角逗号 U+FF0C
    func testXjuWeekSplitAcceptsFullwidthComma() throws {
        let source = """
            <html><body><table id="ctl00_contentParent_dgData">
            <tr><th>节次</th><th>星期一</th></tr>
            <tr><td align="center">1</td>
            <td>｛流体力学(1-8周，10-16周)[教师:钱老师,地点:力学楼-1]｝</td></tr>
            </table></body></html>
        """
        let courses = try JwXjuParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2, "全角逗号分隔的两段周次都要出行(1-8 与 10-16)")
        XCTAssertEqual(Set(courses.map { $0.startWeek }), [1, 10])
    }
}
