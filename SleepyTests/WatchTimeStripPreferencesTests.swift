import XCTest
@testable import Sleepy

final class WatchTimeStripPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "WatchTimeStripPreferencesTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testMissingPreferencesDefaultToTomorrowOff() {
        XCTAssertFalse(AppPrefs(defaults: defaults).isWatchTimeStripTomorrow())
        assertSafeDefaults(WatchTimeStripPreferencesStore(defaults: defaults).load())
        XCTAssertNil(WatchSyncSnapshot.PrefsSnapshot().timeStripTomorrow)
    }

    func testPhoneOptionPersistsTrueAndFalseForIndependentReader() throws {
        let writer = AppPrefs(defaults: defaults)
        let reader = AppPrefs(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))

        for enabled in [true, false] {
            writer.setWatchTimeStripTomorrow(enabled)
            XCTAssertEqual(reader.isWatchTimeStripTomorrow(), enabled)
        }
    }

    func testSharedOptionPersistsTrueAndFalseForIndependentReader() throws {
        let writer = WatchTimeStripPreferencesStore(defaults: defaults)
        let reader = try independentReader()

        for enabled in [true, false] {
            writer.save(WatchTimeStripPreferences(showsTomorrow: enabled))
            XCTAssertEqual(reader.load().showsTomorrow, enabled)
        }
    }

    func testApplyReplacesLanguageAndAllTransferMappings() throws {
        let store = WatchTimeStripPreferencesStore(defaults: defaults)
        let reader = try independentReader()
        let firstJSON = try transferJSON(source: "2026-11-09", target: "2026-11-14")
        let nextJSON = try transferJSON(source: "2026-11-10", target: "2026-11-15")
        var snapshot = WatchSyncSnapshot.PrefsSnapshot()
        snapshot.timeStripTomorrow = true
        snapshot.language = "ja"
        snapshot.transfers = [11: firstJSON, 22: "[]"]
        store.apply(snapshot)

        XCTAssertTrue(reader.load().showsTomorrow)
        XCTAssertEqual(reader.load().language, "ja")
        XCTAssertEqual(reader.load().transfers, [11: firstJSON, 22: "[]"])

        snapshot.timeStripTomorrow = false
        snapshot.language = "es"
        snapshot.transfers = [22: nextJSON]
        store.apply(snapshot)
        let replaced = reader.load()
        XCTAssertFalse(replaced.showsTomorrow)
        XCTAssertEqual(replaced.language, "es")
        XCTAssertEqual(replaced.transfers, [22: nextJSON], "Removed timetables must not retain stale mappings")
        XCTAssertEqual(HolidayTransferOps.decodeTransfers(try XCTUnwrap(replaced.transfers[22])).count, 1)

        snapshot.transfers = [:]
        store.apply(snapshot)
        XCTAssertTrue(reader.load().transfers.isEmpty)
    }

    func testSaveStoresOneCompleteEncodedDataBlob() throws {
        let preferences = WatchTimeStripPreferences(
            showsTomorrow: true, language: "en", transfers: [7: "[]"])
        WatchTimeStripPreferencesStore(defaults: defaults).save(preferences)

        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(domain.count, 1, "The extension must read one snapshot, not separately written fields")
        let data = try XCTUnwrap(domain.values.first as? Data)
        let decoded = try JSONDecoder().decode(WatchTimeStripPreferences.self, from: data)
        XCTAssertTrue(decoded.showsTomorrow)
        XCTAssertEqual(decoded.language, "en")
        XCTAssertEqual(decoded.transfers, [7: "[]"])
    }

    func testMalformedSharedBlobReturnsSafeDefaults() throws {
        let store = WatchTimeStripPreferencesStore(defaults: defaults)
        store.save(WatchTimeStripPreferences(showsTomorrow: true, language: "ja", transfers: [1: "[]"]))
        let key = try XCTUnwrap(defaults.persistentDomain(forName: suiteName)?.keys.first)
        let reader = try independentReader()

        for malformed in ["not-json", #"{"showsTomorrow":"yes","language":"en","transfers":[]}"#] {
            defaults.set(Data(malformed.utf8), forKey: key)
            assertSafeDefaults(reader.load())
        }
    }

    func testPayloadRoundTripKeepsExplicitTomorrowOption() throws {
        for enabled in [true, false] {
            var body = WatchSyncSnapshot.Body()
            body.prefs = WatchSyncSnapshot.PrefsSnapshot(timeStripTomorrow: enabled)
            let context = WatchSyncSnapshot.encodeToApplicationContext(body)
            let decoded = try XCTUnwrap(WatchSyncSnapshot.decode(from: context))
            XCTAssertEqual(decoded.prefs?.timeStripTomorrow, enabled)
        }
    }

    func testOlderPayloadOmittingOptionDecodesAndDisablesPreviousPreview() throws {
        var body = WatchSyncSnapshot.Body()
        body.prefs = WatchSyncSnapshot.PrefsSnapshot(timeStripTomorrow: true)
        var context = WatchSyncSnapshot.encodeToApplicationContext(body)
        var payload = try XCTUnwrap(context[WatchSyncSnapshot.keySyncPayload] as? [String: Any])
        var preferences = try XCTUnwrap(payload["prefs"] as? [String: Any])
        preferences.removeValue(forKey: "timeStripTomorrow")
        payload["prefs"] = preferences
        context[WatchSyncSnapshot.keySyncPayload] = payload

        let decoded = try XCTUnwrap(WatchSyncSnapshot.decode(from: context))
        let oldPreferences = try XCTUnwrap(decoded.prefs)
        XCTAssertNil(oldPreferences.timeStripTomorrow)

        let store = WatchTimeStripPreferencesStore(defaults: defaults)
        store.save(WatchTimeStripPreferences(showsTomorrow: true))
        store.apply(oldPreferences)
        XCTAssertFalse(try independentReader().load().showsTomorrow)
    }

    func testCaptureIncludesCurrentPhoneOption() throws {
        let prefs = AppPrefs.shared
        let previous = prefs.sharedBackedStore.object(forKey: AppPrefs.KEY_WATCH_TIME_STRIP_TOMORROW)
        defer {
            if let previous = previous {
                prefs.sharedBackedStore.set(previous, forKey: AppPrefs.KEY_WATCH_TIME_STRIP_TOMORROW)
            } else {
                prefs.sharedBackedStore.removeObject(forKey: AppPrefs.KEY_WATCH_TIME_STRIP_TOMORROW)
            }
        }
        let repo = ScheduleRepository(try AppDatabase.inMemory())

        for enabled in [true, false] {
            prefs.setWatchTimeStripTomorrow(enabled)
            XCTAssertEqual(WatchSyncSnapshot.capture(repo: repo).prefs?.timeStripTomorrow, enabled)
        }
    }

    private func independentReader() throws -> WatchTimeStripPreferencesStore {
        WatchTimeStripPreferencesStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    private func transferJSON(source: String, target: String) throws -> String {
        HolidayTransferOps.encodeTransfers([
            HolidayTransferEntry(sourceDate: try XCTUnwrap(DateUtils.parseDate(source)),
                                 targetDate: try XCTUnwrap(DateUtils.parseDate(target)),
                                 segmentId: "test-transfer")
        ])
    }

    private func assertSafeDefaults(_ preferences: WatchTimeStripPreferences,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(preferences.showsTomorrow, file: file, line: line)
        XCTAssertEqual(preferences.language, "zh-CN", file: file, line: line)
        XCTAssertTrue(preferences.transfers.isEmpty, file: file, line: line)
    }
}
