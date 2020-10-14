import XCTest
@testable import WasmI32Transformer

final class WasmI32TransformerTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(WasmI32Transformer().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
