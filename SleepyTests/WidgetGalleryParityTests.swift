import XCTest
import SwiftUI
import WidgetKit
@testable import Sleepy

final class WidgetGalleryParityTests: XCTestCase {
    @MainActor
    func testManagementReloadsPlacedWidgetsWhenReturningFromTheHomeScreen() async {
        let initial = expectation(description: "Initial management load")
        let resumed = expectation(description: "Reload after returning from the Home Screen")
        let phase = WidgetManagementTestPhase()
        var loads = 0
        let screen = WidgetManagementScreen(onDismiss: {}, loadItems: {
            loads += 1
            if loads == 1 { initial.fulfill() }
            if loads == 2 { resumed.fulfill() }
            return []
        })
        let host = UIHostingController(rootView: WidgetManagementTestHost(phase: phase, screen: screen))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        await fulfillment(of: [initial], timeout: 3)
        phase.value = .background
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(loads, 1, "Backgrounding must not request widget configuration")
        phase.value = .active
        await fulfillment(of: [resumed], timeout: 3)
        XCTAssertEqual(loads, 2, "Returning must discover the current desktop configurations")
    }

    private func card(_ family: WidgetFamily, kind: String) -> WidgetGalleryCard {
        WidgetGalleryCard(variant: WidgetVariantInfo(kind: kind, displayNameKey: "widget_today_label"),
                          previewFamily: family)
    }

    func testMixedSizeRowUsesLargestAreaAndKeepsPartialLastRow() {
        let cards = [card(.systemSmall, kind: "small"), card(.systemLarge, kind: "large"),
                     card(.systemMedium, kind: "medium"), card(.systemSmall, kind: "small2"),
                     card(.systemSmall, kind: "last")]
        let ratios = WidgetGalleryData.rowBoxAspectRatios(cards, columns: 2)
        XCTAssertEqual(ratios, [329.0 / 345.0, 329.0 / 345.0, 329.0 / 158.0, 329.0 / 158.0, 1.0])
        XCTAssertEqual(WidgetGalleryData.rowBoxAspectRatios([], columns: 2), [])
        XCTAssertEqual(WidgetGalleryData.rowBoxAspectRatios(cards, columns: 1),
                       cards.map { WidgetGalleryData.aspectRatio(of: $0.previewFamily) })
    }

    func testRegisteredFacesShareOneBoxRatioInEachTwoColumnRow() {
        let cards = WidgetGalleryData.buildCards()
        XCTAssertEqual(cards.map(\.variant.kind), allWidgetVariants.map(\.kind))
        let ratios = WidgetGalleryData.rowBoxAspectRatios(cards, columns: 2)
        XCTAssertEqual(ratios.count, cards.count)
        for start in stride(from: 0, to: cards.count - 1, by: 2) {
            XCTAssertEqual(ratios[start], ratios[start + 1])
        }
    }

    func testAccordionListsBothIndependentWideKindsAlongsideTheFullGrid() throws {
        XCTAssertEqual(WeekGridWidget.supportedFamilies, [.systemSmall, .systemLarge],
                       "The system picker must not offer a third complete-grid 4×2 face")
        let groups = WidgetGalleryData.buildGroups()
        XCTAssertEqual(groups.count, 5)
        let grid = try XCTUnwrap(groups.first { $0.id == "WeekGridWidgetV19" })
        XCTAssertEqual(grid.primary.previewFamily, .systemLarge)
        XCTAssertEqual(grid.cards.map(\.variant.kind),
                       ["WeekGridWidgetV19", WeekGridWideMode.vertical.widgetKind,
                        WeekGridWideMode.horizontal.widgetKind, "WeekGridWidgetV19"])
        XCTAssertEqual(grid.cards.map(\.previewFamily), [.systemLarge, .systemMedium, .systemMedium, .systemSmall])
        XCTAssertEqual(Set(groups.flatMap(\.cards).map(\.id)).count, 16)
        XCTAssertTrue(groups.allSatisfy(\.isMultiSize))
        for group in groups {
            let rows = WidgetGalleryData.rows(groups, expandedKey: group.id)
            XCTAssertEqual(rows.filter(\.expanded).count, 1)
            XCTAssertEqual(rows.first { $0.expanded }?.groups.map(\.id), [group.id])
            XCTAssertEqual(rows.flatMap(\.groups).map(\.id), groups.map(\.id))
            XCTAssertTrue(rows.filter { !$0.expanded }.allSatisfy { $0.groups.count <= 2 })
        }
        XCTAssertTrue(WidgetGalleryData.rows(groups, expandedKey: nil).allSatisfy { !$0.expanded })
        XCTAssertTrue(WidgetGalleryData.rows(groups, expandedKey: "removed").allSatisfy { !$0.expanded })
    }

    func testWideGridGeometryClipsLongCoursesAndMeasuresTheVisibleCard() throws {
        let sample = WidgetGallerySampleData.make()
        let now = sample.today.date.addingTimeInterval(13 * 3600)
        var week = sample.week
        let long = CourseEntity(groupId: "wide-long", tableId: -1, courseName: "A long course title",
            room: "A305", day: 2, startNode: 1, step: 12, startWeek: 1, endWeek: 16, color: "#FF6C75E8", id: 998)
        week.days[1] = DayData(date: sample.today.date, dayOfWeek: 2, courses: [long],
                               timeJson: sample.today.timeJson)
        let layout = WeekGridWideGeometry.make(data: week, settings: WeekGridWideSettings(), now: now,
                                               size: CGSize(width: 329, height: 158))
        XCTAssertGreaterThan(layout.window.startIndex, 0)
        let card = try XCTUnwrap(layout.cards.first { $0.course.id == long.id })
        XCTAssertEqual(card.bounds.minY, layout.body.minY + 1, accuracy: 0.01)
        XCTAssertLessThanOrEqual(card.bounds.maxY, layout.body.maxY)
        XCTAssertTrue(layout.body.contains(card.bounds))
        for side in WeekGridWideLabelSide.allCases {
            let horizontal = WeekGridWideGeometry.make(data: week,
                settings: WeekGridWideSettings(mode: .horizontal, labelSide: side), now: now,
                size: CGSize(width: 329, height: 158))
            XCTAssertEqual(horizontal.dates.count, 3)
            XCTAssertEqual(horizontal.window.startIndex, 0)
            XCTAssertEqual(horizontal.window.count, horizontal.periods.count)
            XCTAssertTrue(horizontal.cards.allSatisfy { horizontal.body.contains($0.bounds) })
        }
    }

    func testWideGridTimelineAdvancesAtEveryPeriodEndWithoutCourses() throws {
        let now = try XCTUnwrap(DateUtils.parseDate("2026-11-10"))
        let periods = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},{\"node\":3,\"start\":\"09:00\",\"end\":\"09:45\"}]"
        let data = WeekData(days: [DayData(date: now, dayOfWeek: 2, courses: [], timeJson: periods)], hasTable: true)
        let dates = WeekGridWideWidgetProvider.timelineDates(data: data, mode: .vertical, from: now,
            before: now.addingTimeInterval(12 * 3600))
        XCTAssertEqual(dates.map { Int($0.timeIntervalSince(now) / 60) }, [0, 525, 585])
        XCTAssertEqual(WeekGridWideWidgetProvider.timelineDates(data: data, mode: .horizontal, from: now,
            before: now.addingTimeInterval(12 * 3600)), [now])
    }

    func testWideGridSkipsMalformedLegacyNodeSpansBeforeConflictGeometry() {
        let sample = WidgetGallerySampleData.make()
        let valid = sample.today.courses.first!
        var malformed: [CourseEntity] = []
        for (offset, span) in [(Int.max, 1), (Int.max, Int.max), (1, 0), (1, Int.min), (-1, 2)].enumerated() {
            var course = valid
            course.id = Int64(900 + offset)
            course.startNode = span.0
            course.step = span.1
            malformed.append(course)
            XCTAssertNil(WeekGridWideWindowCore.periodNodeSpan(startNode: span.0, step: span.1))
        }
        XCTAssertEqual(WeekGridWideWindowCore.periodNodeSpan(startNode: 1, step: 2), 1..<3)
        XCTAssertEqual(WeekGridWideWindowCore.periodNodeSpan(startNode: 0, step: 1), 0..<1)
        var data = sample.week
        data.days = [DayData(date: sample.today.date, dayOfWeek: DateUtils.todayDayOfWeek(today: sample.today.date),
                             courses: malformed + [valid], timeJson: sample.today.timeJson)]
        let layout = WeekGridWideGeometry.make(data: data, settings: WeekGridWideSettings(mode: .horizontal),
                                               now: sample.today.date, size: CGSize(width: 329, height: 158))
        XCTAssertEqual(layout.cards.map(\.course.id), [valid.id])
    }

    @MainActor func testWideGridTextFitsClippedNarrowCardsWithoutEllipsisOnly() {
        for size in [CGSize(width: 3, height: 12), CGSize(width: 24, height: 8),
                     CGSize(width: 40, height: 70), CGSize(width: 100, height: 20)] {
            for value in ["高等数学及其应用", "Programming fundamentals with laboratory", "👩🏽‍💻 课程 A305"] {
                let layout = WideGridTextLayout.make(value, width: size.width, height: size.height, preferred: 11)
                XCTAssertFalse(layout.text.isEmpty)
                XCTAssertNotEqual(layout.text, "…")
                let font = UIFont.systemFont(ofSize: layout.size)
                for line in layout.text.components(separatedBy: "\n") {
                    XCTAssertLessThanOrEqual((line as NSString).size(withAttributes: [.font: font]).width, size.width + 0.1)
                }
            }
        }
    }

    func testFixedSampleContainsRealCourseMetadataAndConsistentDays() throws {
        let sample = WidgetGallerySampleData.make()
        XCTAssertTrue(sample.today.hasTable)
        XCTAssertTrue(sample.week.hasTable)
        XCTAssertTrue(sample.twoDay.hasTable)
        XCTAssertEqual(sample.week.days.count, 7)
        XCTAssertEqual(sample.week.visibleDays, Set(1...7))
        XCTAssertEqual(sample.week.days.map { $0.courses.count }, [3, 4, 3, 2, 3, 0, 0])
        XCTAssertEqual(DateUtils.todayDayOfWeek(today: sample.today.date), 2)
        XCTAssertEqual(sample.today.courses, sample.week.days[1].courses)
        XCTAssertEqual(sample.twoDay.days.map(\.date), Array(sample.week.days[1...2]).map(\.date))
        let courses = sample.week.days.flatMap(\.courses)
        XCTAssertEqual(Set(courses.map(\.id)).count, 15)
        for day in sample.week.days {
            XCTAssertEqual(DateUtils.todayDayOfWeek(today: day.date), day.dayOfWeek)
            for course in day.courses {
                XCTAssertEqual(course.day, day.dayOfWeek)
                XCTAssertFalse(course.courseName.isEmpty)
                XCTAssertFalse(course.courseName.hasPrefix("widget_preview_"), "Sample names must be localized")
                XCTAssertFalse(course.room.isEmpty)
                XCTAssertEqual(course.colorMode, 2)
                let time = try XCTUnwrap(TimeTableUtils.courseTimeString(courseStartNode: course.startNode,
                    courseStep: course.step, timeJson: day.timeJson, ownTime: false, startTime: "", endTime: ""))
                XCTAssertFalse(time.isEmpty)
            }
        }
    }

    @available(iOS 16.0, *)
    @MainActor
    func testWideGridProductionModesRenderInBothThemesAtPhoneAndTabletSizes() throws {
        let sample = WidgetGallerySampleData.make()
        let now = sample.today.date.addingTimeInterval(9 * 3600)
        let out = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WidgetWideRender", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for size in [CGSize(width: 300, height: 160), CGSize(width: 358, height: 169)] {
            for mode in WeekGridWideMode.allCases {
                let sides: [WeekGridWideLabelSide] = mode == .horizontal ? [.left, .right] : [.left]
                for side in sides {
                    for dark in [false, true] {
                        let entry = WeekGridWideWidgetEntry(date: now, data: sample.week,
                            settings: WeekGridWideSettings(mode: mode, labelSide: side))
                        let renderer = ImageRenderer(content: WeekGridWideWidgetEntryView(entry: entry)
                            .environment(\.sleepyWidgetGalleryFamily, .systemMedium)
                            .environment(\.sleepyWidgetGalleryDate, now)
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .frame(width: size.width, height: size.height))
                        renderer.proposedSize = ProposedViewSize(size)
                        renderer.scale = 2
                        let rendered = try XCTUnwrap(renderer.uiImage)
                        let png = try XCTUnwrap(rendered.pngData())
                        XCTAssertEqual(rendered.size.width, size.width, accuracy: 1)
                        XCTAssertEqual(rendered.size.height, size.height, accuracy: 1)
                        XCTAssertGreaterThan(png.count, 2_000)
                        let name = "wide-\(mode.rawValue)-\(side.rawValue)-\(dark ? "dark" : "light")-\(Int(size.width))"
                        try png.write(to: out.appendingPathComponent(name + ".png"))
                        let attachment = XCTAttachment(image: rendered)
                        attachment.name = name
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        NSLog("WIDGET_WIDE_RENDER_WRITTEN %@", out.appendingPathComponent(name + ".png").path)
                    }
                }
            }
        }
    }

    @available(iOS 16.0, *)
    @MainActor
    func testIndependentWideKindsRenderBoundCoursesWithDistinctAxes() async throws {
        let cache = AppPrefs.shared.sharedBackedStore
        let cacheKeys = ["holiday_entries_2426", "holiday_entries_2426_loaded"]
        let previousCache = cacheKeys.map { cache.object(forKey: $0) }
        cache.set("[]", forKey: cacheKeys[0]); cache.set(true, forKey: cacheKeys[1])
        defer {
            for (key, value) in zip(cacheKeys, previousCache) {
                if let value { cache.set(value, forKey: key) } else { cache.removeObject(forKey: key) }
            }
        }
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        let periods = (0..<8).map { index in
            ["node": index + 1, "start": String(format: "%02d:00", 8 + index),
             "end": String(format: "%02d:45", 8 + index)] as [String: Any]
        }
        let times = String(data: try JSONSerialization.data(withJSONObject: periods), encoding: .utf8)!
        let periodTable = try repository.insertPeriodTable(PeriodTableEntity(name: "Eight periods",
            nodesPerDay: 8, timeJson: times))
        let table = try repository.insertTable(TimeTableEntity(name: "Bound render fixture",
            startDate: "2426-11-09", nodesPerDay: 1, timeJson: "[]", periodTableId: periodTable))
        for (day, node, step, name, room) in [(1, 1, 8, "Monday studio", "M100"),
                                             (2, 2, 2, "Drawing", "A305"),
                                             (3, 5, 2, "Seminar", "B406"),
                                             (4, 7, 2, "Laboratory", "C507")] {
            try repository.insertCourse(CourseEntity(groupId: "render-\(day)", tableId: table,
                courseName: name, room: room, day: day, startNode: node, step: step,
                startWeek: 1, endWeek: 16, color: "#E57D9C", colorMode: 2))
        }
        let kind = "widget-independent-render-\(UUID().uuidString)"
        WidgetBindingStore.put(kind, tableId: table)
        defer { WidgetBindingStore.remove(kind) }
        let morning = try XCTUnwrap(DateUtils.parseDate("2426-11-10")).addingTimeInterval(7.5 * 3600)
        let resolved = await WidgetWeekDataLoader.resolve(kind, repository: repository, now: morning)
        let source = try XCTUnwrap(resolved)
        XCTAssertEqual(source.table.timeJson, times, "The render must use the bound independent period table")
        XCTAssertEqual(source.courses.count, 4)

        let prefs = AppPrefs.shared
        let oldColorless = prefs.isWidgetColorless()
        let oldSeparators = prefs.isGridShowSeparators()
        prefs.setWidgetColorless(false)
        prefs.setGridShowSeparators(false)
        defer {
            prefs.setWidgetColorless(oldColorless)
            prefs.setGridShowSeparators(oldSeparators)
        }
        let size = CGSize(width: 358, height: 169)
        let wholeImage = CGRect(origin: .zero, size: size)
        var images: [WeekGridWideMode: UIImage] = [:]
        for mode in WeekGridWideMode.allCases {
            var data = await WeekGridWideDataLoader.dataForSource(source, mode: mode, now: morning)
            data.themeKey = ThemePresets.KEY_DEFAULT
            data.themeMode = "light"
            data.isDark = false
            data.showDate = true
            // Holiday preferences must not change the deterministic fixture's contrast.
            data.days = data.days.map { DayData(date: $0.date, dayOfWeek: $0.dayOfWeek,
                courses: $0.courses, timeJson: $0.timeJson) }
            let expectedDates = mode == .horizontal
                ? ["2426-11-10", "2426-11-11", "2426-11-12"]
                : ["2426-11-09", "2426-11-10", "2426-11-11", "2426-11-12",
                   "2426-11-13", "2426-11-14", "2426-11-15"]
            XCTAssertEqual(data.days.map { HolidayTransferOps.dayKey($0.date) }, expectedDates)
            XCTAssertTrue(data.days.allSatisfy { $0.timeJson == times })
            XCTAssertEqual(Set(data.days.flatMap(\.courses).map(\.courseName)), mode == .horizontal
                ? Set(["Drawing", "Seminar", "Laboratory"])
                : Set(["Monday studio", "Drawing", "Seminar", "Laboratory"]))
            let settings = WeekGridWideSettings(mode: mode)
            let image = try renderWideMode(data: data, settings: settings, now: morning, size: size)
            images[mode] = image
            try attachWideMode(image, name: mode.rawValue)
            XCTAssertGreaterThan(try saturatedPixelCount(image), 100,
                                 "\(mode) must draw the real courses' custom color")

            var withoutText = data
            withoutText.days = data.days.map { day in
                DayData(date: day.date, dayOfWeek: day.dayOfWeek, courses: day.courses.map { course in
                    var copy = course
                    copy.courseName = ""
                    copy.alias = ""
                    copy.room = ""
                    return copy
                }, timeJson: day.timeJson)
            }
            let blankCards = try renderWideMode(data: withoutText, settings: settings, now: morning, size: size)
            XCTAssertGreaterThan(try differingPixels(image, blankCards, in: wholeImage), 20,
                                 "\(mode) must draw course names and room text, not just colored cards")

            let geometry = WeekGridWideGeometry.make(data: data, settings: settings, now: morning, size: size)
            XCTAssertEqual(geometry.dates.count, mode == .vertical ? 7 : 3)
            XCTAssertEqual(geometry.periods.map(\.node), Array(1...8))
            XCTAssertFalse(geometry.cards.isEmpty)
            XCTAssertTrue(geometry.cards.allSatisfy { geometry.body.contains($0.bounds) })
            var empty = data
            empty.days = data.days.map { DayData(date: $0.date, dayOfWeek: $0.dayOfWeek,
                courses: [], timeJson: $0.timeJson) }
            let axes = try renderWideMode(data: empty, settings: settings, now: morning, size: size)
            for card in geometry.cards {
                XCTAssertGreaterThan(try differingPixels(image, axes, in: card.bounds.insetBy(dx: 2, dy: 2)), 10,
                                     "\(mode) must draw the visible card for \(card.course.courseName)")
            }
            if mode == .vertical {
                XCTAssertEqual(geometry.body.minX, 28)
                XCTAssertEqual(geometry.body.minY, 6, "Android's vertical mode has no date header")
                XCTAssertEqual(geometry.window, WidePeriodWindow(startIndex: 0, count: 4))
                XCTAssertGreaterThan(try darkPixelCount(axes, in: CGRect(x: 0, y: 6, width: 28, height: 157)), 15,
                                     "Vertical must draw its left period-number axis")
                let afternoon = morning.addingTimeInterval(5.5 * 3600)
                let advanced = WeekGridWideGeometry.make(data: data, settings: settings, now: afternoon, size: size)
                XCTAssertEqual(advanced.window, WidePeriodWindow(startIndex: 4, count: 4))
                XCTAssertEqual(Set(advanced.cards.map(\.course.courseName)),
                               ["Monday studio", "Seminar", "Laboratory"])
                let advancedImage = try renderWideMode(data: data, settings: settings, now: afternoon, size: size)
                XCTAssertGreaterThan(try differingPixels(image, advancedImage, in: wholeImage), 100)
                try attachWideMode(advancedImage, name: "vertical-afternoon")
            } else {
                XCTAssertEqual(geometry.body.minX, 40)
                XCTAssertEqual(geometry.body.minY, 40)
                XCTAssertEqual(geometry.window, WidePeriodWindow(startIndex: 0, count: 8))
                XCTAssertEqual(Set(geometry.cards.map(\.course.courseName)), ["Drawing", "Seminar", "Laboratory"])
                XCTAssertGreaterThan(try darkPixelCount(axes, in: CGRect(x: 0, y: 40, width: 34, height: 123)), 15,
                                     "Horizontal must draw three date rows")
                var untimed = empty
                let nodeOnly = String(data: try JSONSerialization.data(withJSONObject:
                    (1...8).map { ["node": $0] }), encoding: .utf8)!
                untimed.days = empty.days.map { DayData(date: $0.date, dayOfWeek: $0.dayOfWeek,
                    courses: [], timeJson: nodeOnly) }
                let untimedAxes = try renderWideMode(data: untimed, settings: settings, now: morning, size: size)
                XCTAssertGreaterThan(try differingPixels(axes, untimedAxes,
                    in: CGRect(x: 40, y: 17, width: 312, height: 23)), 20,
                    "Horizontal must draw start/end clock text below its period numbers")
                let rightSettings = WeekGridWideSettings(mode: .horizontal, labelSide: .right)
                let right = WeekGridWideGeometry.make(data: data, settings: rightSettings, now: morning, size: size)
                XCTAssertEqual(right.dates, geometry.dates)
                XCTAssertEqual(right.body.minX, 6)
                XCTAssertEqual(right.body.maxX, size.width - 40)
                let rightImage = try renderWideMode(data: data, settings: rightSettings, now: morning, size: size)
                XCTAssertGreaterThan(try differingPixels(image, rightImage, in: wholeImage), 100)
                let afternoon = WeekGridWideGeometry.make(data: data, settings: settings,
                    now: morning.addingTimeInterval(5.5 * 3600), size: size)
                XCTAssertEqual(afternoon.window, geometry.window, "Horizontal must never advance the period window")
                try attachWideMode(rightImage, name: "horizontal-right")
            }
        }
        XCTAssertGreaterThan(try differingPixels(XCTUnwrap(images[.vertical]), XCTUnwrap(images[.horizontal]),
            in: wholeImage), 100, "The two independent widgets must render visibly distinct layouts")
    }

    @available(iOS 16.0, *)
    @MainActor
    private func renderWideMode(data: WeekData, settings: WeekGridWideSettings, now: Date, size: CGSize) throws -> UIImage {
        try renderWideContent(WeekGridWideWidgetEntryView(entry:
            WeekGridWideWidgetEntry(date: now, data: data, settings: settings)), now: now, size: size)
    }

    @available(iOS 16.0, *)
    @MainActor
    private func renderWideContent<Content: View>(_ content: Content, now: Date, size: CGSize) throws -> UIImage {
        let renderer = ImageRenderer(content: content
            .environment(\.sleepyWidgetGalleryFamily, .systemMedium)
            .environment(\.sleepyWidgetGalleryDate, now)
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    private func widePixels(_ image: UIImage, in rect: CGRect? = nil) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let original = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(original.width) / image.size.width
        let bounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        let area = rect.map { $0.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            .intersection(bounds) } ?? bounds
        guard !area.isNull, !area.isEmpty else { return ([], 0, 0) }
        // CGImage cropping uses image coordinates, avoiding a CGContext row-order assumption.
        let cg = try XCTUnwrap(original.cropping(to: area))
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: cg.width,
                height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return (bytes, cg.width, cg.height)
    }

    private func differingPixels(_ first: UIImage, _ second: UIImage, in rect: CGRect) throws -> Int {
        let a = try widePixels(first, in: rect), b = try widePixels(second, in: rect)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        return stride(from: 0, to: min(a.bytes.count, b.bytes.count), by: 4).filter { offset in
            (0..<4).contains { abs(Int(a.bytes[offset + $0]) - Int(b.bytes[offset + $0])) > 8 }
        }.count
    }

    private func saturatedPixelCount(_ image: UIImage) throws -> Int {
        let pixels = try widePixels(image)
        return stride(from: 0, to: pixels.bytes.count, by: 4).filter { offset in
            let rgb = pixels.bytes[offset..<(offset + 3)]
            return Int(rgb.max()!) - Int(rgb.min()!) > 40 && pixels.bytes[offset + 3] > 128
        }.count
    }

    private func darkPixelCount(_ image: UIImage, in rect: CGRect) throws -> Int {
        let pixels = try widePixels(image, in: rect)
        return stride(from: 0, to: pixels.bytes.count, by: 4).filter { offset in
            pixels.bytes[offset + 3] > 128 && (0..<3).allSatisfy { pixels.bytes[offset + $0] < 150 }
        }.count
    }

    private func attachWideMode(_ image: UIImage, name: String) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WidgetModeVerification", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: path)
        let attachment = XCTAttachment(image: image)
        attachment.name = "widget-mode-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        NSLog("WIDGET_MODE_VERIFICATION_WRITTEN %@", path.path)
    }

    @available(iOS 16.0, *)
    @MainActor
    func testUniformColorReachesEveryColoredProductionWidgetFace() throws {
        let sample = WidgetGallerySampleData.make()
        var week = sample.week
        week.themeMode = "light"
        week.themeKey = ThemePresets.KEY_DEFAULT
        week.days = week.days.map { day in
            DayData(date: day.date, dayOfWeek: day.dayOfWeek, courses: day.courses.map { row in
                var course = row
                course.color = ""
                course.colorMode = CourseColorMode.GROUP
                return course
            }, timeJson: day.timeJson)
        }
        let now = sample.today.date.addingTimeInterval(7 * 3600)
        let prefs = AppPrefs.shared
        let previous = prefs.isWidgetColorless()
        defer { prefs.setWidgetColorless(previous) }
        let size = CGSize(width: 358, height: 169)
        let neutral = resolveWidgetScheme(themeKey: week.themeKey, isDark: false).secondaryContainer
        for kind in ["WeekGridWidgetV19", "TodayWidgetRV", "TwoDayWidgetRV", "WeekListWidgetRV",
                     WeekGridWideMode.vertical.widgetKind, WeekGridWideMode.horizontal.widgetKind] {
            func content() -> AnyView {
                switch kind {
                case "WeekGridWidgetV19":
                    return AnyView(WeekGridWidgetEntryView(entry: .init(date: now, data: week)))
                case "TodayWidgetRV":
                    let today = WidgetData(date: sample.today.date, courses: week.days[1].courses,
                        timeJson: sample.today.timeJson, hasTable: true, themeKey: week.themeKey,
                        themeMode: "light", isToday: true)
                    return AnyView(TodayWidgetEntryView(entry: .init(date: now, data: today)))
                case "TwoDayWidgetRV":
                    return AnyView(TwoDayWidgetEntryView(entry: .init(date: now,
                        data: TwoDayData(days: Array(week.days[1...2]), hasTable: true,
                            themeKey: week.themeKey, themeMode: "light"))))
                case "WeekListWidgetRV":
                    return AnyView(WeekListWidgetEntryView(entry: .init(date: now, data: week)))
                default:
                    return AnyView(WeekGridWideWidgetEntryView(entry: .init(date: now, data: week,
                        settings: .init(mode: WeekGridWideMode(kind: kind)!))))
                }
            }
            prefs.setWidgetColorless(false)
            let colored = try renderWideContent(content(), now: now, size: size)
            prefs.setWidgetColorless(true)
            let uniform = try renderWideContent(content(), now: now, size: size)
            XCTAssertGreaterThan(try colorPixelCount(uniform, color: neutral),
                                 try colorPixelCount(colored, color: neutral) + 100,
                                 "\(kind) must use the selected theme's secondaryContainer when uniform color is enabled")
            try attachWideMode(uniform, name: "uniform-" + kind)
        }
    }

    private func colorPixelCount(_ image: UIImage, color: Color) throws -> Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let target = [red, green, blue].map { Int(($0 * 255).rounded()) }
        let pixels = try widePixels(image)
        return stride(from: 0, to: pixels.bytes.count, by: 4).filter { offset in
            pixels.bytes[offset + 3] > 240 &&
                (0..<3).allSatisfy { abs(Int(pixels.bytes[offset + $0]) - target[$0]) <= 4 }
        }.count
    }

    @available(iOS 16.0, *)
    @MainActor
    func testAllProductionPreviewFacesRenderInsideTheirSharedRowBoxes() throws {
        let cards = WidgetGalleryData.buildCards()
        let ratios = WidgetGalleryData.rowBoxAspectRatios(cards, columns: 2)
        let out = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WidgetGalleryRender", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (index, card) in cards.enumerated() {
            let size = CGSize(width: 164, height: 164 / ratios[index])
            let renderer = ImageRenderer(content: WidgetGalleryPreview(card: card)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(size)
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage, card.variant.kind)
            let png = try XCTUnwrap(rendered.pngData(), card.variant.kind)
            XCTAssertEqual(rendered.size.width, size.width, accuracy: 1)
            XCTAssertEqual(rendered.size.height, size.height, accuracy: 1)
            XCTAssertGreaterThan(png.count, 2_000, "Preview should contain rendered course content")
            let path = out.appendingPathComponent(card.variant.kind + ".png")
            try png.write(to: path)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "widget-gallery-" + card.variant.kind
            attachment.lifetime = .keepAlways
            add(attachment)
            NSLog("WIDGET_GALLERY_PREVIEW_WRITTEN %@", path.path)
        }
    }
}

@MainActor
private final class WidgetManagementTestPhase: ObservableObject {
    @Published var value: ScenePhase = .inactive
}

private struct WidgetManagementTestHost: View {
    @ObservedObject var phase: WidgetManagementTestPhase
    let screen: WidgetManagementScreen

    var body: some View {
        screen.environment(\.scenePhase, phase.value)
    }
}
