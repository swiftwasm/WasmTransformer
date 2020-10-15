@testable import WasmTransformer
import XCTest
import JavaScriptCore

class IntegrationTests: XCTestCase {
    func testSwiftFoundationDate() throws {
        let binaryPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/build/main.wasm")
        
        let transformer = I64Transformer()
        var inputStream = try InputStream(from: binaryPath)
        let writer = InMemoryOutputWriter()
        try transformer.transform(&inputStream, writer: writer)

        let (url, handle) = makeTemporaryFile()
        handle.write(Data(writer.bytes))
        print(url)
        let vm = JSVirtualMachine()!
        let context = JSContext(virtualMachine: vm)!
        let script = """
        
        """
        context.evaluateScript(<#T##script: String!##String!#>)

        runWasm(url)
    }
}
