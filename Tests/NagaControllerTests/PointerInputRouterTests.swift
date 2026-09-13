import XCTest
@testable import NagaController

final class PointerInputRouterTests: XCTestCase {
    private let bindings: [Int: HardwareBinding] = [
        7: .init(usagePage: 12, usage: 568, cookie: 896, value: -1, vendorID: 1678, productID: 181),
        8: .init(usagePage: 12, usage: 568, cookie: 896, value: 1, vendorID: 1678, productID: 181),
        9: .init(usagePage: 9, usage: 3, cookie: 24, value: 1, vendorID: 1678, productID: 181)
    ]
    private func index(page: UInt32 = 12, usage: UInt32 = 568, cookie: UInt32 = 896, value: Int32,
                       vendor: Int = 1678, product: Int = 181) -> Int? {
        PointerInputRouter.bindingIndex(bindings: bindings, usagePage: page, usage: usage,
            cookie: cookie, value: value, vendorID: vendor, productID: product)
    }
    func testTiltDirectionsAndRepeatMagnitude() {
        XCTAssertEqual(index(value: -1), 7)
        XCTAssertEqual(index(value: 1), 8)
        XCTAssertEqual(index(value: -3), 7)
        XCTAssertEqual(index(value: 4), 8)
        XCTAssertNil(index(value: 0))
    }
    func testMiddleDownAndUpAreRoutedWithoutInterceptingPrimaryButtons() {
        XCTAssertEqual(index(page: 9, usage: 3, cookie: 24, value: 1), 9)
        XCTAssertEqual(index(page: 9, usage: 3, cookie: 24, value: 0), 9)
        XCTAssertNil(index(page: 9, usage: 1, cookie: 22, value: 1))
        XCTAssertNil(index(page: 9, usage: 2, cookie: 23, value: 1))
    }
    func testUnrelatedDevicesAndVerticalScrollingDoNotMatch() {
        XCTAssertNil(index(value: 1, vendor: 1452))
        XCTAssertNil(index(value: 1, product: 999))
        XCTAssertNil(index(page: 1, usage: 56, value: 1))
    }
    func testOneObservationCannotTriggerTwice() {
        var router = PointerInputRouter()
        router.record(.init(kind: .horizontalScroll, timestamp: 100_000_000, buttonIndex: 7))
        XCTAssertEqual(router.consume(kind: .horizontalScroll, timestamp: 101_000_000), 7)
        XCTAssertNil(router.consume(kind: .horizontalScroll, timestamp: 101_000_000))
    }
    func testDelayedCallbacksAndNaturalScrollingUseHIDDirection() {
        var router = PointerInputRouter()
        router.record(.init(kind: .horizontalScroll, timestamp: 120_000_000, buttonIndex: 8))
        XCTAssertEqual(router.consume(kind: .horizontalScroll, timestamp: 100_000_000), 8)
    }
    func testExpiredAndWrongEventKindsPassThrough() {
        var router = PointerInputRouter()
        router.record(.init(kind: .button(usage: 3, down: true), timestamp: 100_000_000, buttonIndex: 9))
        XCTAssertNil(router.consume(kind: .horizontalScroll, timestamp: 100_000_000))
        XCTAssertNil(router.consume(kind: .button(usage: 3, down: false), timestamp: 100_000_000))
        XCTAssertNil(router.consume(kind: .button(usage: 3, down: true), timestamp: 200_000_000))
    }
}
