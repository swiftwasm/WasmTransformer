import WasmTransformer
import Foundation
import XCTest
import PythonKit

final class I64ImportTransformerTests: XCTestCase {

    let binaryPath = buildPath.appendingPathComponent("I64ImportTransformerTests.wasm")

    func lowerI64Imports(_ input: URL) throws -> URL {
        let transformer = I64ImportTransformer()
        var inputStream = try InputByteStream(from: binaryPath)
        var writer = InMemoryOutputWriter()
        try transformer.transform(&inputStream, writer: &writer)

        let (url, wasmFileHandle) = makeTemporaryFile(suffix: ".wasm")
        wasmFileHandle.write(Data(writer.bytes()))
        return url
    }

    func testIntegration() throws {
        let html = try createCheckHtml(embedding: lowerI64Imports(binaryPath))
        let (tmpHtmlURL, htmlFileHandle) = makeTemporaryFile(suffix: ".html")
        htmlFileHandle.write(html.data(using: .utf8)!)
        
        
        // Ensure that no exception happen
        let time = Python.import("time")
        let webdriver = Python.import("selenium.webdriver")
        
        let driver = webdriver.Safari()
        driver.set_page_load_timeout(120)
        driver.get(tmpHtmlURL.absoluteString)
        time.sleep(5)
        driver.execute_async_script("await window.I64ImportTransformerTests(wasmBytes);arguments[0]();")
        time.sleep(5)
        driver.quit()
    }
}
