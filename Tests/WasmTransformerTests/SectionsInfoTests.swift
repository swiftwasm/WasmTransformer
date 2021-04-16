@testable import WasmTransformer
import XCTest

final class SectionsInfoTests: XCTestCase {
    func testSectionsInfo() throws {
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
        var input = try InputByteStream(bytes: [UInt8](Data(contentsOf: binaryURL)))
        try XCTAssertEqual(
            input.readSectionsInfo(),
            [
                .init(startOffset: 8,  contentStart: 10, type: .type, size: 5),
                .init(startOffset: 15, contentStart: 17, type: .function, size: 2),
                .init(startOffset: 19, contentStart: 21, type: .code, size: 9),
                .init(startOffset: 30, contentStart: 32, type: .custom, size: 18),
            ]
        )
    }
}
