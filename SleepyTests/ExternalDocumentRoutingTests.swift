import XCTest
import UniformTypeIdentifiers
@testable import Sleepy

final class ExternalDocumentRoutingTests: XCTestCase {
    @MainActor
    private func openDocument(_ text: String, extension ext: String) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = PendingImportText.value
        PendingImportText.value = nil
        defer { PendingImportText.value = previous }

        let delivered = expectation(description: "Document payload delivered before the mounted importer consumes it")
        var receivedText: String?
        XCTAssertTrue(ImportReceiverActivity.receiveIfFileURL(url, onReceived: {
            XCTAssertTrue(Thread.isMainThread)
            receivedText = PendingImportText.value
            delivered.fulfill()
        }))
        await fulfillment(of: [delivered], timeout: 3)
        return try XCTUnwrap(receivedText)
    }

    @MainActor
    func testOpeningJSONDocumentDeliversImportPreviewPayload() async throws {
        let json = "{\"name\":\"外部课表\",\"courses\":[{\"name\":\"数学\",\"day\":1,\"startNode\":1,\"step\":1,\"startWeek\":1,\"endWeek\":16}]}"
        let delivered = try await openDocument(json, extension: "json")
        XCTAssertEqual(delivered, json)
        let result = try ScheduleParser.parse(delivered, defaultTableId: 1).get()
        XCTAssertEqual(result.tableName, "外部课表")
        XCTAssertEqual(result.courses.map(\.courseName), ["数学"])
    }

    @MainActor
    func testOpeningNativeDocumentDeliversImportableCourse() async throws {
        let text = "#sleepy-v1\nT外部原生表|2026-11-02|16|12\nC物理|1|1-2|1-16"
        let delivered = try await openDocument(text, extension: "sleepy")
        XCTAssertEqual(delivered, text)
        XCTAssertEqual(try ScheduleParser.parse(delivered, defaultTableId: 1).get().courses.map(\.courseName), ["物理"])
    }

    func testDocumentRouteLeavesAppAndWebURLsToTheirOwnHandlers() throws {
        XCTAssertFalse(ImportReceiverActivity.receiveIfFileURL(try XCTUnwrap(URL(string: "sleepy://course/1"))))
        XCTAssertFalse(ImportReceiverActivity.receiveIfFileURL(try XCTUnwrap(URL(string: "https://example.com/course.json"))))
    }

    func testBundleRegistersAllSupportedExternalTextFormats() throws {
        let types = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        let accepted = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        for identifier in [UTType.json.identifier, UTType.plainText.identifier, UTType.html.identifier,
                           UTType.xml.identifier, UTType.commaSeparatedText.identifier,
                           "com.apple.ical.ics", "com.lingion.sleepy.schedule"] {
            XCTAssertTrue(accepted.contains(identifier), "Missing external document type: \(identifier)")
        }
        XCTAssertFalse(accepted.contains(UTType.data.identifier), "Opening arbitrary binary files must not enter the text importer")
        XCTAssertFalse(accepted.contains(UTType.zip.identifier))
    }

    func testNativeExtensionHasAnExportedPlainTextType() throws {
        let exported = try XCTUnwrap(Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]])
        let native = try XCTUnwrap(exported.first { $0["UTTypeIdentifier"] as? String == "com.lingion.sleepy.schedule" })
        XCTAssertTrue((native["UTTypeConformsTo"] as? [String] ?? []).contains(UTType.plainText.identifier))
        let tags = try XCTUnwrap(native["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["sleepy"])
    }
}
