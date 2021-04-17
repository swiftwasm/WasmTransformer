@testable import WasmTransformer
import XCTest

final class StackOverflowSanitizerTests: XCTestCase {

    func testTransformFunction() throws {
        let wat = """
        (module
          (import "__stack_sanitizer" "report_stack_overflow" (func))
          (global (mut i32) (i32.const 0))
          (func $bar
            call $foo
          )
          (func $foo)
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
        000059 func[3]:
         00005a: 01 7f                      | local[0] type=i32
         00005c: 41 00                      | i32.const 0
         00005e: 21 00                      | local.set 0
         000060: 20 00                      | local.get 0
         000062: 41 00                      | i32.const 0
         000064: 48                         | i32.lt_s
         000065: 04 40                      | if
         000067: 10 00                      |   call 0 <__stack_sanitizer.report_stack_overflow>
         000069: 0b                         | end
         00006a: 20 00                      | local.get 0
         00006c: 24 00                      | global.set 0
         00006e: 0b                         | end
        """
        XCTAssertContains(disassemble, contains: expected)
    }
}
