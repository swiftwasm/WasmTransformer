import XCTest
@testable import WasmTransformer

final class WasmTransformerTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(WasmTransformer().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
