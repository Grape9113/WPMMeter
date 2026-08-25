import XCTest
@testable import WPMMeter

final class WPMEstimatorTests: XCTestCase {
    func testHostApplicationHasStableBundleIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.grape9113.WPMMeter")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "WPMMeter")
    }

    func testReportsKnownRate() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "a", start: 0, end: 10, wordCount: 25))
        XCTAssertEqual(estimator.value(at: 10), 150)
    }

    func testRequiresEnoughWordsAndTime() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "a", start: 0, end: 4, wordCount: 4))
        XCTAssertNil(estimator.value(at: 4))
        estimator.replace(.init(id: "a", start: 0, end: 2, wordCount: 10))
        XCTAssertNil(estimator.value(at: 2))
    }

    func testVolatileCorrectionReplacesOverlappingEvidence() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "volatile-1", start: 0, end: 10, wordCount: 25))
        estimator.replace(.init(id: "volatile-2", start: 0, end: 10, wordCount: 50))
        XCTAssertEqual(estimator.value(at: 10), 300)
    }

    func testCorrectionCanDeletePreviouslyRecognizedWords() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "old", start: 0, end: 10, wordCount: 25))
        estimator.replace(rangeStart: 0, rangeEnd: 10, with: [])
        XCTAssertNil(estimator.value(at: 10))
        XCTAssertTrue(estimator.batches.isEmpty)
    }

    func testShortPauseHoldsThenBecomesUnavailableAndResets() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "a", start: 0, end: 10, wordCount: 25))
        XCTAssertEqual(estimator.value(at: 14.9), 150)
        XCTAssertNil(estimator.value(at: 15))
        XCTAssertNil(estimator.value(at: 18))
        XCTAssertTrue(estimator.batches.isEmpty)
    }

    func testLongPauseIsIncludedWhenSpeechResumesBeforeEpisodeEnds() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "a", start: 0, end: 5, wordCount: 15))
        estimator.replace(.init(id: "b", start: 11, end: 15, wordCount: 10))
        XCTAssertEqual(estimator.value(at: 15), 100)
    }

    func testOldEvidenceExpires() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "old", start: 0, end: 5, wordCount: 25))
        estimator.replace(.init(id: "new", start: 16, end: 20, wordCount: 10))
        XCTAssertEqual(estimator.batches.map(\.id), ["new"])
    }

    func testImplausibleResultIsUnavailable() {
        var estimator = WPMEstimator()
        estimator.replace(.init(id: "a", start: 0, end: 3, wordCount: 100))
        XCTAssertNil(estimator.value(at: 3))
    }
}
