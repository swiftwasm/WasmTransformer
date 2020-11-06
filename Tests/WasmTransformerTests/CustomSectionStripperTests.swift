import XCTest
@testable import WasmTransformer

private func transformWat(_ input: String) throws -> URL {
    let inputWasm = compileWat(input, options: ["--debug-names"])
    let transformer = CustomSectionStripper()
    var inputStream = try InputByteStream(from: inputWasm)
    let writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: writer)

    let (url, handle) = makeTemporaryFile()
    handle.write(Data(writer.bytes()))
    return url
}

final class CustomSectionStripperTests: XCTestCase {
    func testStripDebugSection() throws {
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
        do {
            let original = compileWat(wat, options: ["--debug-names"])
            let output = wasmObjdump(original, args: ["--header"])
            let expectedCustomSection = #"Custom start=0x00000020 end=0x00000032 (size=0x00000012) "name""#
            XCTAssertTrue(output.contains(expectedCustomSection))
        }
        do {
            let url = try transformWat(wat)
            let output = wasmObjdump(url, args: ["--header"])
            XCTAssertFalse(output.contains("Custom start="))
        }
    }
}
