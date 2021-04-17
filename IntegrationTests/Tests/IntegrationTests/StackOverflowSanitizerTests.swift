import WasmTransformer
import Foundation
import XCTest
import PythonKit

final class StackOverflowSanitizerTests: XCTestCase {

    let binaryPath = buildPath.appendingPathComponent("StackOverflowSanitizerTests.wasm")

    func instrumentStackSanitizer(_ input: URL) throws -> URL {
        let transformer = StackOverflowSanitizer()
        var inputStream = try InputByteStream(from: binaryPath)
        var writer = InMemoryOutputWriter()
        try transformer.transform(&inputStream, writer: &writer)

        let (url, wasmFileHandle) = makeTemporaryFile(suffix: ".wasm")
        wasmFileHandle.write(Data(writer.bytes()))
        return url
    }

    func testIntegration() throws {
        let wasm = try instrumentStackSanitizer(binaryPath)
        let html = try createCheckHtml(embedding: wasm)
        let (tmpHtmlURL, htmlFileHandle) = makeTemporaryFile(suffix: ".html")
        htmlFileHandle.write(html.data(using: .utf8)!)
        
        
        // Ensure that no exception happen
        let time = Python.import("time")
        let webdriver = Python.import("selenium.webdriver")
        
        let driver = webdriver.Safari()
        driver.set_page_load_timeout(120)
        driver.get(tmpHtmlURL.absoluteString)
        time.sleep(5)
        let entryScript = "await window.StackOverflowSanitizerTests(wasmBytes);arguments[0]();"
        XCTAssertThrowsError(
            try driver.execute_async_script.throwing.dynamicallyCall(withArguments: entryScript)
        ) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("CATCH_STACK_OVERFLOW"), description)
        }
        driver.quit()
    }
}
