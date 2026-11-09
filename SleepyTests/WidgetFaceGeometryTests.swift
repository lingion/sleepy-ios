import XCTest
import SwiftUI
import WidgetKit
import UIKit
@testable import Sleepy

final class WidgetFaceGeometryTests: XCTestCase {
    func testGridHeaderDoesNotHighlightSameWeekdayInAnotherWeek() throws {
        let today = try XCTUnwrap(DateUtils.parseDate("2026-10-20"))
        let nextTuesday = try XCTUnwrap(DateUtils.parseDate("2026-10-27"))
        let current = DayData(date: today, dayOfWeek: 2, courses: [], timeJson: "")
        let next = DayData(date: nextTuesday, dayOfWeek: 2, courses: [], timeJson: "")
        XCTAssertTrue(WidgetFaceGeometry.isToday(current, referenceDate: today))
        XCTAssertFalse(WidgetFaceGeometry.isToday(next, referenceDate: today))
        XCTAssertFalse(WidgetFaceGeometry.isToday(nil, referenceDate: today))
    }

    func testTwoDayFooterUsesActualColumnBudgetForLargeCountsAndNarrowFamilies() {
        XCTAssertEqual(WidgetFaceGeometry.footerWidth(textWidth: 12, columnWidth: 145), 28)
        XCTAssertEqual(WidgetFaceGeometry.footerWidth(textWidth: 50, columnWidth: 145), 66)
        XCTAssertEqual(WidgetFaceGeometry.footerWidth(textWidth: 50, columnWidth: 42), 42)
        XCTAssertEqual(WidgetFaceGeometry.footerWidth(textWidth: 50, columnWidth: 0), 0)
    }

    func testRoomLabelStaysInsideItsBottomReserveOnTallAndShortCards() {
        for height: CGFloat in [9, 18, 40, 120] {
            let reserve = min(7.7, max(height - 8, 0) * 0.35)
            let layout = WidgetFaceGeometry.gridRoomLabel(cardHeight: height,
                reserveHeight: reserve, requestedSize: 8)
            XCTAssertLessThanOrEqual(layout.size * 1.1, reserve + 0.0001)
            XCTAssertGreaterThanOrEqual(layout.baseline - layout.size * 0.8,
                                       height - 4 - reserve - 0.0001)
            XCTAssertLessThanOrEqual(layout.baseline + layout.size * 0.3, height - 4 + 0.0001)
        }
        let empty = WidgetFaceGeometry.gridRoomLabel(cardHeight: 3, reserveHeight: 0, requestedSize: 8)
        XCTAssertEqual(empty.size, 0)
    }

    func testGalleryMatchesSevenDaySampleAndTagCoursePalette() {
        let sample = WidgetGallerySampleData.make()
        XCTAssertEqual(sample.week.visibleDays, Set(1...7))
        XCTAssertEqual(Set(sample.week.days.flatMap(\.courses).map(\.color)),
                       ["#D9B7EA", "#EAEAB7", "#B7EAD1", "#B7C4EA", "#EAB7D9", "#EAD1B7"])
    }

    @available(iOS 16.0, *)
    @MainActor
    func testSmallGridProductionFaceUsesTodayOnlyBelow150Points() throws {
        let sample = WidgetGallerySampleData.make()
        let entry = WeekGridWidgetEntry(date: sample.today.date, data: sample.week)
        func grid(width: CGFloat, family: WidgetFamily) throws -> UIImage {
            try render(WeekGridWidgetEntryView(entry: entry)
                .environment(\.sleepyWidgetGalleryFamily, family)
                .environment(\.sleepyWidgetGalleryDate, sample.today.date),
                size: CGSize(width: width, height: 158))
        }
        func today(width: CGFloat) throws -> UIImage {
            try render(TodayWidgetEntryView(entry: entry.minimumTodayEntry)
                .environment(\.sleepyWidgetGalleryFamily, .systemSmall)
                .environment(\.sleepyWidgetGalleryDate, sample.today.date),
                size: CGSize(width: width, height: 158))
        }

        let narrow = try grid(width: 149, family: .systemSmall)
        XCTAssertTrue(try pixels(narrow).elementsEqual(pixels(today(width: 149))),
                      "A narrow small widget must render the real Today face")
        XCTAssertFalse(try pixels(narrow).elementsEqual(pixels(grid(width: 149, family: .systemMedium))),
                       "A medium widget must retain its grid even below 150pt")
        try attach(narrow, name: "WeekGridWidgetV19-small-149-today")
        for width: CGFloat in [150, 158] {
            let small = try grid(width: width, family: .systemSmall)
            let regular = try grid(width: width, family: .systemMedium)
            XCTAssertTrue(try pixels(small).elementsEqual(pixels(regular)),
                          "At \(width)pt the small widget must render the real grid face")
            XCTAssertFalse(try pixels(small).elementsEqual(pixels(today(width: width))),
                           "The wide small widget must stop rendering Today content")
            XCTAssertTrue(try pixels(regular).elementsEqual(pixels(grid(width: width, family: .systemLarge))),
                          "Medium and large families must retain their grid")
            try attach(small, name: "WeekGridWidgetV19-small-\(Int(width))-grid")
        }
    }

    @available(iOS 16.0, *)
    @MainActor
    private func render<Content: View>(_ content: Content, size: CGSize) throws -> UIImage {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var result = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try result.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cgImage.width,
                height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return result
    }

    private func attach(_ image: UIImage, name: String) throws {
        let out = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WidgetFaceGeometry", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let path = out.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: path)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        NSLog("WIDGET_SIZE_PARITY_WRITTEN %@", path.path)
    }

    @available(iOS 16.0, *)
    @MainActor
    func testCanvasBaselineTextMovesInkByRequestedBaselineDistance() throws {
        func inkBounds(baseline: CGFloat) throws -> (min: Int, max: Int) {
            let renderer = ImageRenderer(content: WidgetBaselineText(
                text: Text("Hg").font(.system(size: 12)).foregroundColor(.black),
                width: 80, height: 80, baseline: baseline))
            renderer.scale = 1
            let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage)
            var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            return try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cgImage.width,
                    height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                let rgba = bytes.bindMemory(to: UInt8.self)
                let rows = (0..<cgImage.height).filter { y in
                    (0..<cgImage.width).contains { x in rgba[(y * cgImage.width + x) * 4 + 3] > 16 }
                }
                return (try XCTUnwrap(rows.first), try XCTUnwrap(rows.last))
            }
        }
        let first = try inkBounds(baseline: 20)
        let second = try inkBounds(baseline: 60)
        XCTAssertEqual(abs(second.min - first.min), 40)
        XCTAssertEqual(second.max - second.min, first.max - first.min)
    }
}
