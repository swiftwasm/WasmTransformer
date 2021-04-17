@testable import WasmTransformer
import XCTest

final class StackOverflowSanitizerTests: XCTestCase {

    func testTransformFunction() throws {
        let wat = """
        (module
          (global (mut i32) (i32.const 0))
          (func $llvm_func
            i32.const 0
            global.set 0
          )
        )
        """

        let binaryURL = compileWat(wat)
        var input = try InputByteStream(bytes: [UInt8](Data(contentsOf: binaryURL)))

        var writer = InMemoryOutputWriter()
        let transformer = StackOverflowSanitizer()
        try transformer.transform(&input, writer: &writer)
        let (url, handle) = makeTemporaryFile()
        handle.write(Data(writer.bytes()))
        let disassemble = wasmObjdump(url, args: ["--disassemble"])
        let expected = """
        000045 func[1]:
         000046: 01 7f                      | local[0] type=i32
         000048: 41 00                      | i32.const 0
         00004a: 21 00                      | local.set 0
         00004c: 20 00                      | local.get 0
         00004e: 41 00                      | i32.const 0
         000050: 48                         | i32.lt_s
         000051: 04 40                      | if
         000053: 10 00                      |   call 0 <__stack_sanitizer.report_stack_overflow>
         000055: 0b                         |   end
        """
        XCTAssertContains(disassemble, contains: expected)
    }
}
