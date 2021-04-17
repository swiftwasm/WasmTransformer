import WasmTransformer
import Foundation

let buildPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/build")

func makeTemporaryFile(suffix: String) -> (URL, FileHandle) {
    let tempdir = URL(fileURLWithPath: NSTemporaryDirectory())
    let templatePath = tempdir.appendingPathComponent("wasm-transformer.XXXXXX\(suffix)")
    var template = [UInt8](templatePath.path.utf8).map { Int8($0) } + [Int8(0)]
    let fd = mkstemps(&template, Int32(suffix.utf8.count))
    if fd == -1 {
        fatalError("Failed to create temp directory")
    }
    let url = URL(fileURLWithPath: String(cString: template))
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    return (url, handle)
}
extension InputByteStream {
    init(from url: URL) throws {
        let bytes = try Array(Data(contentsOf: url))
        self.init(bytes: bytes)
    }
}

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

let html = try createCheckHtml(embedding: lowerI64Imports(binaryPath))
let (tmpHtmlURL, htmlFileHandle) = makeTemporaryFile(suffix: ".html")
htmlFileHandle.write(html.data(using: .utf8)!)


// Ensure that no exception happen
import PythonKit

let time = Python.import("time")
let webdriver = Python.import("selenium.webdriver")

let driver = webdriver.Safari()
driver.set_page_load_timeout(120)
driver.get(tmpHtmlURL.absoluteString)
time.sleep(5)
driver.execute_async_script("await window.startWasiTask(wasmBytes);arguments[0]();")
time.sleep(5)
driver.quit()
