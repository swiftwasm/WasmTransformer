import XCTest

import WasmI32TransformerTests

var tests = [XCTestCaseEntry]()
tests += WasmI32TransformerTests.allTests()
XCTMain(tests)
