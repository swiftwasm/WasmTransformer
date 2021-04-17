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
        00001e func[0]:
         00001f: 01 7f                      | local[0] type=i32
         000021: 41 00                      | i32.const 0
         000023: 21 00                      | local.set 0
         000025: 20 00                      | local.get 0
         000027: 41 00                      | i32.const 0
         000029: 48                         | i32.lt_s
         00002a: 04 40                      | if
         00002c: 00                         |   unreachable
         00002d: 0b                         |   end
        """
        XCTAssertTrue(disassemble.contains(expected))
    }
}
