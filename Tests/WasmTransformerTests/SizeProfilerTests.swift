@testable import WasmTransformer
import XCTest

final class SizeProfilerTests: XCTestCase {
    func testSizeProfiler() throws {
        let wat = """
        (module
          (func $add (result i32)
            (i32.add
              (i32.const 1)
              (i32.const 1)
            )
          )
        )
        """

        let binaryURL = compileWat(wat, options: ["--debug-names"])
        let binary = try [UInt8](Data(contentsOf: binaryURL))
        try XCTAssertEqual(
            sizeProfiler(binary),
            [
                .init(startOffset: 8, endOffset: 15, type: .type, size: 5),
                .init(startOffset: 15, endOffset: 19, type: .function, size: 2),
                .init(startOffset: 19, endOffset: 30, type: .code, size: 9),
                .init(startOffset: 30, endOffset: 50, type: .custom, size: 18),
            ]
        )
    }
}
