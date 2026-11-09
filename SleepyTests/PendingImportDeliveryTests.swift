import XCTest
@testable import Sleepy

final class PendingImportDeliveryTests: XCTestCase {
    @MainActor
    func testExistingObserverConsumesTwoFileOpensAndIgnoresClearing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstText = "#sleepy-v1\nT第一张表|2026-11-02|16|12\nC数学|1|1-2|1-16"
        let secondText = "#sleepy-v1\nT第二张表|2026-11-02|16|12\nC物理|2|3-4|1-16"
        let firstURL = directory.appendingPathComponent("first.sleepy")
        let secondURL = directory.appendingPathComponent("second.sleepy")
        try Data(firstText.utf8).write(to: firstURL)
        try Data(secondText.utf8).write(to: secondURL)
        let previous = PendingImportText.value
        PendingImportText.value = nil
        defer { PendingImportText.value = previous }

        let firstDelivered = expectation(description: "already mounted importer receives first document")
        let secondDelivered = expectation(description: "same importer receives the next document")
        var delivered: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: PendingImportText.changedNotification, object: nil, queue: .main
        ) { _ in
            guard let text = PendingImportText.value,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            XCTAssertTrue(Thread.isMainThread)
            delivered.append(text)
            // A mounted importer consumes immediately. The resulting nil notification
            // must not reopen the sheet or count as another document delivery.
            PendingImportText.value = nil
            if delivered.count == 1 { firstDelivered.fulfill() }
            if delivered.count == 2 { secondDelivered.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertTrue(ImportReceiverActivity.receiveIfFileURL(firstURL))
        await fulfillment(of: [firstDelivered], timeout: 3)
        XCTAssertEqual(delivered, [firstText])
        XCTAssertNil(PendingImportText.value)

        XCTAssertTrue(ImportReceiverActivity.receiveIfFileURL(secondURL))
        await fulfillment(of: [secondDelivered], timeout: 3)
        XCTAssertEqual(delivered, [firstText, secondText])
        XCTAssertNil(PendingImportText.value)
        PendingImportText.value = nil
        XCTAssertEqual(delivered.count, 2)
    }
}
