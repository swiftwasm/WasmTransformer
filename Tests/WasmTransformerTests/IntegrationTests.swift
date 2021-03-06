@testable import WasmTransformer
import XCTest

class IntegrationTests: XCTestCase {
    func testSwiftFoundationDate() throws {
        let binaryPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/build/main.wasm")
        
        let transformer = I64ImportTransformer()
        var inputStream = try InputByteStream(from: binaryPath)
        let writer = InMemoryOutputWriter()
        try transformer.transform(&inputStream, writer: writer)
    }
}
