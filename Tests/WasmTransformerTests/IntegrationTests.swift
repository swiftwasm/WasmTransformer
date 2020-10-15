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
        var inputStream = try InputByteStream(from: binaryPath)
        let writer = InMemoryOutputWriter()
        try transformer.transform(&inputStream, writer: writer)
    }
}
