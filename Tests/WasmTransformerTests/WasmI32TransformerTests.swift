@testable import WasmTransformer
import XCTest

func transformWat(_ input: String) throws -> URL {
    let inputWasm = compileWat(input)
    let transformer = I64Transformer()
    var inputStream = try InputStream(from: inputWasm)
    let writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: writer)

    let (url, handle) = makeTemporaryFile()
    handle.write(Data(writer.bytes))
    return url
}

final class WasmTransformerTests: XCTestCase {

    func testTransformI64ParamsImport() throws {
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
}
