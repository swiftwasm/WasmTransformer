import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(WasmI32TransformerTests.allTests),
    ]
}
#endif
