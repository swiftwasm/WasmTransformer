import XCTest

import WasmTransformerTests

var tests = [XCTestCaseEntry]()
tests += WasmTransformerTests.allTests()
XCTMain(tests)
