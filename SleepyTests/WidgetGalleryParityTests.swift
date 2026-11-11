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

    func testAccordionGroupsEverySupportedSizeAndKeepsWideGridInItsFamily() throws {
        let groups = WidgetGalleryData.buildGroups()
        XCTAssertEqual(groups.count, 5)
        let grid = try XCTUnwrap(groups.first { $0.id == "WeekGridWidgetV19" })
        XCTAssertEqual(grid.primary.previewFamily, .systemLarge)
        XCTAssertEqual(grid.cards.count, 4)
        XCTAssertEqual(grid.cards.filter { $0.variant.kind == WeekGridWideSettings.kind }.map(\.previewFamily), [.systemMedium])
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
