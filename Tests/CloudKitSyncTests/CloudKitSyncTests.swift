import XCTest
@testable import CloudKitSync

final class CloudKitSyncTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(CloudKitSync().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
