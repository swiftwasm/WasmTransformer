@testable import WasmTransformer
import XCTest

func transformWat(_ input: String) throws -> URL {
    let inputWasm = compileWat(input)
    let transformer = I64ImportTransformer()
    var inputStream = try InputByteStream(from: inputWasm)
    let writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: writer)

    let (url, handle) = makeTemporaryFile()
    handle.write(Data(writer.bytes()))
    return url
}

final class WasmTransformerTests: XCTestCase {

    func testI64ParamsImport() throws {
        let wat = """
        (module
            (import "foo" "bar" (func (param i64)))
        )
        """
        let url = try transformWat(wat)
        let output = wasmObjdump(url, args: ["--details"])
        let expectedTypes = """
        Type[2]:
         - type[0] (i64) -> nil
         - type[1] (i32) -> nil
        """
        XCTAssertTrue(output.contains(expectedTypes))
        let expectedImport = """
        Import[1]:
         - func[0] sig=1 <foo.bar> <- foo.bar
        """
        XCTAssertTrue(output.contains(expectedImport))
    }

    func testI64ImportCall() throws {
        typealias TestCase = (
            line: UInt, wat: String, expectedTypes: String?, expectedImport: String?, expectedCode: String?
        )
        
        let testCases: [TestCase] = [
            (line: #line,
                wat: """
                (module
                    (import "foo" "bar" (func (param i64)))
                    (func (call 0 (i64.const 0)))
                )
                """,
                expectedTypes: """
                Type[3]:
                 - type[0] (i64) -> nil
                 - type[1] () -> nil
                 - type[2] (i32) -> nil
                """,
                expectedImport: """
                Import[1]:
                 - func[0] sig=2 <foo.bar> <- foo.bar
                """,
                expectedCode: """
                00002c func[1]:
                 00002d: 42 00                      | i64.const 0
                 00002f: 10 02                      | call 2
                 000031: 0b                         | end
                000033 func[2]:
                 000034: 20 00                      | local.get 0
                 000036: a7                         | i32.wrap_i64
                 000037: 10 00                      | call 0 <foo.bar>
                 000039: 0b                         | end
                """
            ),
            (line: #line,
                wat: """
                (module
                    (import "foo" "bar" (func (param i64) (param i32) (param i64)))
                    (func (call 0 (i64.const 0) (i32.const 0) (i64.const 0)))
                )
                """,
                expectedTypes: """
                Type[3]:
                 - type[0] (i64, i32, i64) -> nil
                 - type[1] () -> nil
                 - type[2] (i32, i32, i32) -> nil
                """,
                expectedImport: "func[0] sig=2 <foo.bar> <- foo.bar",
                expectedCode: """
                000030 func[1]:
                 000031: 42 00                      | i64.const 0
                 000033: 41 00                      | i32.const 0
                 000035: 42 00                      | i64.const 0
                 000037: 10 02                      | call 2
                 000039: 0b                         | end
                00003b func[2]:
                 00003c: 20 00                      | local.get 0
                 00003e: a7                         | i32.wrap_i64
                 00003f: 20 01                      | local.get 1
                 000041: 20 02                      | local.get 2
                 000043: a7                         | i32.wrap_i64
                 000044: 10 00                      | call 0 <foo.bar>
                 000046: 0b                         | end
                """
            ),
        ]
        
        for testCase in testCases {
            let url = try transformWat(testCase.wat)
            let summary = wasmObjdump(url, args: ["--details"])
            if let expectedTypes = testCase.expectedTypes {
                XCTAssertTrue(summary.contains(expectedTypes), "\(summary) doesn't contains \(expectedTypes)", line: testCase.line)
            }
            if let expectedImport = testCase.expectedImport {
                XCTAssertTrue(summary.contains(expectedImport), "\(summary) doesn't contains \(expectedImport)", line: testCase.line)
            }
            let disassemble = wasmObjdump(url, args: ["--disassemble"])
            if let expectedCode = testCase.expectedCode {
                XCTAssertTrue(disassemble.contains(expectedCode), "\(disassemble) doesn't contains \(expectedCode)", line: testCase.line)
            }
        }
    }
}
