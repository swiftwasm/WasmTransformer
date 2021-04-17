import WasmTransformer
import Foundation
import XCTest
import PythonKit

let binaryPath = buildPath.appendingPathComponent("main.wasm")
let bundleJSPath = buildPath.appendingPathComponent("bundle.js")

func lowerI64Imports(_ input: URL) throws -> URL {
    let transformer = I64ImportTransformer()
    var inputStream = try InputByteStream(from: binaryPath)
    var writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: &writer)

    let (url, wasmFileHandle) = makeTemporaryFile(suffix: ".wasm")
    wasmFileHandle.write(Data(writer.bytes()))
    return url
}

func createCheckHtml(embedding binaryPath: URL) throws -> String {
    let wasmBytes = try Data(contentsOf: binaryPath)
    return try """
    <script>
    \(String(contentsOf: bundleJSPath))
    function base64ToUint8Array(base64Str) {
        const raw = atob(base64Str);
        return Uint8Array.from(Array.prototype.map.call(raw, (x) => {
            return x.charCodeAt(0);
        }));
    }
    const wasmBytes = base64ToUint8Array(\"\(wasmBytes.base64EncodedString())\")
    </script>
    """
}

final class I64ImportTransformerTests: XCTestCase {

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
        driver.execute_async_script("await window.startWasiTask(wasmBytes);arguments[0]();")
        time.sleep(5)
        driver.quit()
    }
}
