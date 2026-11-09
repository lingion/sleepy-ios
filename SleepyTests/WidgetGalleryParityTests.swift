import XCTest
import SwiftUI
import WidgetKit
@testable import Sleepy

final class WidgetGalleryParityTests: XCTestCase {
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
