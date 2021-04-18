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
        00005b func[3]:
         00005c: 41 00                      | i32.const 0
         00005e: 10 04                      | call 4
         000060: 24 00                      | global.set 0
         000062: 0b                         | end
        000064 func[4]:
         000065: 20 00                      | local.get 0
         000067: 41 00                      | i32.const 0
         000069: 48                         | i32.lt_s
         00006a: 04 40                      | if
         00006c: 10 00                      |   call 0 <__stack_sanitizer.report_stack_overflow>
         00006e: 0b                         | end
         00006f: 20 00                      | local.get 0
         000071: 0b                         | end
        """
        XCTAssertContains(disassemble, contains: expected)
    }
}
