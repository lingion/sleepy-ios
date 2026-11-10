import XCTest
@testable import Sleepy

final class EffectivePeriodResolverTests: XCTestCase {
    private func slots(_ spec: String, first: Int = 1, native: Bool = false) -> [[String: Any]] {
        spec.split(separator: " ").enumerated().map { index, clocks in
            let pair = clocks.split(separator: "-").map(String.init)
            return [native ? "node" : "number": first + index,
                    native ? "start" : "startTime": pair[0], native ? "end" : "endTime": pair[1]]
        }
    }
    private func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self) }
    private func rule(_ start: String = "2026-01-01", _ end: String = "2026-12-31", _ differences: [[String: Any]] = []) -> [String: Any] {
        ["name": "source rule", "startDate": start, "endDate": end, "timeSlots": differences]
    }
    private func combo(_ rules: [[String: Any]] = []) throws -> String { try json(["publicSchedules": rules]) }
    private var basic: String { #"[{"number":1,"startTime":"08:00","endTime":"08:45"},{"number":2,"startTime":"09:00","endTime":"09:45"}]"# }
    private func invalid(_ base: String? = nil, _ combination: String? = nil, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try EffectivePeriodResolver.validate(baseJson: base ?? basic, comboJson: combination ?? combo()), file: file, line: line)
    }

    func testPartialSeasonClosedBoundsAndGapFallback() throws {
        let winter = slots("08:00-08:50 09:00-09:50 10:10-11:00 11:10-12:00 14:00-14:50 15:00-15:50 16:10-17:00 17:10-18:00 19:30-20:20 20:30-21:20")
        var summer = rule("2026-05-01", "2026-10-04", slots("14:30-15:20 15:30-16:20 16:40-17:30 17:40-18:30", first: 5))
        summer["defaultClassDuration"] = 50
        let plan = try EffectivePeriodResolver.validate(baseJson: json(winter), comboJson: combo([summer]))
        XCTAssertEqual(plan.publicSchedules[0].defaultClassDuration, 50)
        for day in ["2026-05-01", "2026-10-04"] {
            let rows = TimeTableUtils.parseTimeSlotRows(try plan.resolve(date: day))
            XCTAssertEqual(rows.count, 10); XCTAssertEqual(rows[4].start, "14:30"); XCTAssertEqual(rows[8].start, "19:30")
        }
        for day in ["2026-04-30", "2026-10-05", "2027-05-01"] {
            XCTAssertEqual(try plan.resolve(date: day), plan.baseTimeJson)
        }
    }

    func testSevenSchoolSeasonVectorsPreserveConcreteYearsAndClocks() throws {
        let vectors: [(String, String)] = [
            ("08:00-08:45 08:55-09:40 10:10-10:55 11:05-11:50 14:00-14:45 14:55-15:40 16:00-16:45 16:55-17:40 19:00-19:45 19:50-20:35 20:40-21:25", "08:00-08:45 08:55-09:40 10:10-10:55 11:05-11:50 14:30-15:15 15:25-16:10 16:30-17:15 17:25-18:10 19:30-20:15 20:20-21:05 21:10-21:55"),
            ("08:00-08:50 09:00-09:50 10:10-11:00 11:10-12:00 13:10-14:00 14:00-14:50 15:00-15:50 16:00-16:50 17:00-17:50 17:50-18:30 19:00-19:50 20:00-20:50 21:00-21:50", "08:00-08:50 09:00-09:50 10:10-11:00 11:10-12:00 12:40-13:30 13:30-14:20 14:30-15:20 15:30-16:20 16:30-17:20 17:20-18:00 18:30-19:20 19:30-20:20 20:30-21:20"),
            ("08:00-08:45 08:55-09:40 10:00-10:45 10:55-11:40 14:30-15:15 15:25-16:10 16:30-17:15 17:25-18:10 19:00-19:45 19:55-20:40", "08:00-08:45 08:55-09:40 10:00-10:45 10:55-11:40 14:00-14:45 14:55-15:40 16:00-16:45 16:55-17:40 19:00-19:45 19:55-20:40"),
            ("08:00-08:45 08:55-09:40 10:10-10:55 11:05-11:50 14:00-14:45 14:55-15:40 16:00-16:45 16:55-17:40 19:00-19:45 19:55-20:40 20:50-21:35", "08:00-08:45 08:55-09:40 10:10-10:55 11:05-11:50 13:30-14:15 14:25-15:10 15:30-16:15 16:25-17:10 18:30-19:15 19:25-20:10 20:20-21:05"),
            ("08:20-09:05 09:15-10:00 10:20-11:05 11:15-12:00 14:30-15:15 15:25-16:10 16:30-17:15 17:25-18:10 19:30-20:15 20:25-21:10", "08:00-08:45 08:55-09:40 10:00-10:45 10:55-11:40 15:00-15:45 15:55-16:40 17:00-17:45 17:55-18:40 20:00-20:45 20:55-21:40"),
            ("08:00-08:45 08:50-09:35 09:50-10:35 10:40-11:25 11:30-12:15 13:30-14:15 14:20-15:05 15:20-16:05 16:10-16:55 18:00-18:45 18:50-19:35 19:40-20:25 20:30-21:15 21:20-22:05", "08:00-08:45 08:50-09:35 09:50-10:35 10:40-11:25 11:30-12:15 14:00-14:45 14:50-15:35 15:50-16:35 16:40-17:25 18:30-19:15 19:20-20:05 20:10-20:55 21:00-21:45 21:50-22:35")
        ]
        for (base, changed) in vectors {
            let plan = try EffectivePeriodResolver.validate(baseJson: json(slots(base)), comboJson: combo([rule("2027-05-01", "2027-09-30", slots(changed))]))
            let expected = slots(changed).map { TimeTableUtils.TimeSlotRow(node: $0["number"] as! Int, start: $0["startTime"] as! String, end: $0["endTime"] as! String) }
            for day in ["2027-05-01", "2027-09-30"] { XCTAssertEqual(try plan.resolve(date: day), TimeTableUtils.buildTimeJsonFromRows(expected)) }
            for day in ["2027-04-30", "2027-10-01", "2028-05-01"] { XCTAssertEqual(try plan.resolve(date: day), plan.baseTimeJson) }
        }
    }

    func testFirstMatchPriorityIncludingEmptyDifferencesAndLeapDay() throws {
        let changed = rule("2028-02-29", "2028-02-29", slots("10:00-10:45", first: 2))
        let empty = rule("2028-02-01", "2028-03-31")
        let first = try EffectivePeriodResolver.validate(baseJson: basic, comboJson: combo([changed, empty]))
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(try first.resolve(date: "2028-02-29"))[1].start, "10:00")
        let second = try EffectivePeriodResolver.validate(baseJson: basic, comboJson: combo([empty, changed]))
        XCTAssertEqual(try second.resolve(date: "2028-02-29"), second.baseTimeJson)
        XCTAssertEqual(try first.resolve(date: "2028-03-01"), first.baseTimeJson)
    }

    func testNativeBaseEdgesUnsortedDifferencesAndCanonicalOutput() throws {
        var base = slots("08:00-08:45 09:00-09:45", native: true); base[0]["edge"] = "before"; base[1]["edge"] = "after"
        let diffs = slots("10:00-10:45", first: 2) + slots("08:15-09:00", first: 1)
        let result = try EffectivePeriodResolver.resolve(baseJson: json(base), comboJson: combo([rule("2026-01-01", "2026-12-31", diffs)]), date: "2026-06-01")
        XCTAssertEqual(result, TimeTableUtils.buildTimeJsonFromRows([
            .init(node: 1, start: "08:15", end: "09:00", edgeClass: .before), .init(node: 2, start: "10:00", end: "10:45", edgeClass: .after)]))
    }

    func testDurationMetadataDefaultsAndOptionalName() throws {
        var r = rule(); r["defaultClassDuration"] = Int64(9_007_199_254_740_991); r["defaultBreakDuration"] = 0
        let plan = try EffectivePeriodResolver.validate(baseJson: basic, comboJson: combo([r, rule()]))
        XCTAssertNil(plan.name); XCTAssertEqual(plan.publicSchedules[0].defaultClassDuration, 9_007_199_254_740_991)
        XCTAssertEqual(plan.publicSchedules[0].defaultBreakDuration, 0); XCTAssertEqual(plan.publicSchedules[1].defaultClassDuration, 45)
        XCTAssertEqual(plan.publicSchedules[1].defaultBreakDuration, 10); XCTAssertEqual(try plan.resolve(date: "2026-01-01"), plan.baseTimeJson)
        XCTAssertEqual(try EffectivePeriodResolver.validate(baseJson: basic, comboJson: #"{"name":"","publicSchedules":[]}"#).name, "")
    }

    func test366PeriodsAndRejectsEmptyAnd367() throws {
        func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
        let rows = (1...366).map { ["number": $0, "startTime": clock($0 - 1), "endTime": clock($0)] as [String: Any] }
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(try EffectivePeriodResolver.validate(baseJson: json(rows), comboJson: combo()).baseTimeJson).count, 366)
        try invalid("[]"); try invalid(json(rows + [["number": 367, "startTime": "06:06", "endTime": "06:07"]]))
    }

    func testRejectsInvalidBaseAndDifferenceIdentities() throws {
        for pair in [[0, 1], [1, 1], [1, 3], [2, 1], [1, 367]] {
            var rows = slots("08:00-08:45 09:00-09:45"); for i in 0..<2 { rows[i]["number"] = pair[i] }; try invalid(json(rows))
        }
        for diffs in [slots("10:00-10:45 11:00-11:45", first: 2), slots("10:00-10:45", first: 0), slots("10:00-10:45", first: 3), slots("10:00-10:45", first: 2) + slots("11:00-11:45", first: 2)] {
            try invalid(nil, combo([rule("2026-01-01", "2026-12-31", diffs)]))
        }
    }

    func testRejectsNumericCoercionAndDuplicateEscapedKeys() throws {
        for raw in ["\"1\"", "true", "null", "1.5", "1.0", "1e0", "9223372036854775808"] {
            try invalid(basic.replacingOccurrences(of: "\"number\":1", with: "\"number\":" + raw))
        }
        for raw in [#"[{"number":1,"number":1,"startTime":"08:00","endTime":"08:45"}]"#,
                    #"[{"number":1,"num\u0062er":1,"startTime":"08:00","endTime":"08:45"}]"#] { try invalid(raw) }
        try invalid(nil, #"{"publicSchedules":[],"publicSchedules":[]}"#)
    }

    func testRejectsClockTypesMalformedClocksAndOverlaps() throws {
        for bad in ["", "8:00", "08:0", " 08:00", "08:00 ", "24:00", "08:60", "08:00:00", "08:00\n"] {
            var rows = slots("08:00-08:45"); rows[0]["startTime"] = bad; try invalid(json(rows))
        }
        for bad in ["08:00-08:00", "08:45-08:00", "23:30-00:15", "08:00-09:01 09:00-09:45"] { try invalid(json(slots(bad))) }
        for bad in ["08:30-09:15", "07:00-07:45"] { try invalid(nil, combo([rule("2026-01-01", "2026-12-31", slots(bad, first: 2))])) }
        try invalid(nil, combo([rule(), rule("2030-01-01", "2030-12-31", slots("08:30-09:15", first: 2))]))
    }

    func testRejectsMalformedDatesWithoutCalendarNormalization() throws {
        for bad in ["2026-02-29", "2028-02-30", "2026-04-31", "2026-13-01", "2026-00-01", "2026-1-01", "2026-01-1", " 2026-01-01", "2026-01-01 ", "2026-01-01T00:00:00", "0000-01-01"] {
            try invalid(nil, combo([rule(bad, "2028-12-31")]))
            XCTAssertThrowsError(try EffectivePeriodResolver.resolve(baseJson: basic, comboJson: combo(), date: bad))
        }
        try invalid(nil, combo([rule("2026-10-08", "2026-10-07")]))
    }

    func testRejectsWrongRuleFieldsDurationsAndMixedDialects() throws {
        for key in ["name", "startDate", "endDate", "timeSlots"] {
            var r = rule(); r.removeValue(forKey: key); try invalid(nil, combo([r])); r[key] = NSNull(); try invalid(nil, combo([r]))
        }
        for key in ["defaultClassDuration", "defaultBreakDuration"] {
            for value in ["45", 1.5, true, NSNull(), -1, Int64(9_007_199_254_740_992)] as [Any] {
                var r = rule(); r[key] = value; try invalid(nil, combo([r]))
            }
        }
        for raw in [#"[{"node":1,"number":1,"start":"08:00","end":"08:45"}]"#,
                    #"[{"node":1,"start":"08:00","end":"08:45"},{"number":2,"startTime":"09:00","endTime":"09:45"}]"#,
                    #"[{"node":1,"start":"08:00"}]"#, #"[{"node":1,"start":"08:00","end":"08:45","edge":"unknown"}]"#] { try invalid(raw) }
    }

    func testRejectsMalformedAndLenientJSON() throws {
        for raw in ["", "[", "null", "{}", "[null]", "[1]", "[{}]", "[{'number':1,'startTime':'08:00','endTime':'08:45'}]", "[{number:1,startTime:\"08:00\",endTime:\"08:45\"}]", basic + " trailing", "[" + basic + ",]"] { try invalid(raw) }
        for raw in ["", "{", "{'publicSchedules':[]}", "{publicSchedules:[]}", "{\"publicSchedules\":[],}", "{\"publicSchedules\":[]} trailing", "[]", "null", "{\"publicSchedules\":null}", "{\"publicSchedules\":{}}", "{\"publicSchedules\":[null]}", "{\"publicSchedules\":[],\"name\":null}"] { try invalid(nil, raw) }
    }
}
