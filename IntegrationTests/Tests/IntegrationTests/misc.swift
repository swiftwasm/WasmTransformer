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

let bundleJSPath = buildPath.appendingPathComponent("bundle.js")
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

import WasmTransformer

extension InputByteStream {
    init(from url: URL) throws {
        let bytes = try Array(Data(contentsOf: url))
        self.init(bytes: bytes)
    }
}

