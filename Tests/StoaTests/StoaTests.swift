import XCTest
@testable import StoaKit

final class StoaTests: XCTestCase {
    func testVersion() throws {
        XCTAssertEqual(StoaKit.version, "0.1.0")
    }
}
