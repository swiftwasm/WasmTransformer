import Foundation

@discardableResult
func exec(_ launchPath: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.launch()
    process.waitUntilExit()
    assert(process.terminationStatus == 0)
    guard let stdoutData = try? stdoutPipe.fileHandleForReading.readToEnd(),
          let stdout = String(data: stdoutData, encoding: .utf8) else {
        return nil
    }
    return stdout
}

func makeTemporaryFile() -> (URL, FileHandle) {
    let tempdir = URL(fileURLWithPath: NSTemporaryDirectory())
    let templatePath = tempdir.appendingPathComponent("wasm-transformer.XXXXXX")
    var template = [UInt8](templatePath.path.utf8).map { Int8($0) } + [Int8(0)]
    let fd = mkstemp(&template)
    if fd == -1 {
        fatalError("Failed to create temp directory")
    }
    let url = URL(fileURLWithPath: String(cString: template))
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    return (url, handle)
}

func createFile(_ content: String) -> URL {
    let (url, handle) = makeTemporaryFile()
    handle.write(content.data(using: .utf8)!)
    return url
}

func compileWat(_ content: String, options: [String] = []) -> URL {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    let path = ProcessInfo.processInfo.environment["WASM_TRANSFORMER_WAT2WASM"] ?? "/usr/local/bin/wat2wasm"
    exec(path, [module.path, "-o", output.path] + options)
    return output
}

func runWasm(_ input: URL) {
    exec("/usr/local/bin/wasmtime", [input.path])
}

func wasmObjdump(_ input: URL, args: [String]) -> String {
    exec("/usr/local/bin/wasm-objdump", [input.path] + args)!
}


@testable import WasmTransformer

extension WasmTransformer.InputStream {
    init(from url: URL) throws {
        let bytes = try Array(Data(contentsOf: url))
        self.init(bytes: bytes)
    }
}
