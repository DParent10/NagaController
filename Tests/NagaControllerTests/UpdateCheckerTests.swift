import XCTest
@testable import NagaController

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatchVersionIsDetected() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.3", than: "0.2.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.2", than: "0.2.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.1", than: "0.2.2"))
    }

    func testNewerMinorAndMajorVersionsAreDetected() {
        XCTAssertTrue(UpdateChecker.isNewer("0.3.0", than: "0.2.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testDifferentSegmentCountsCompareCorrectly() {
        // "0.3" vs "0.2.9": missing trailing segments count as 0, not "shorter therefore older".
        XCTAssertTrue(UpdateChecker.isNewer("0.3", than: "0.2.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2", than: "0.2.0"))
    }
}
