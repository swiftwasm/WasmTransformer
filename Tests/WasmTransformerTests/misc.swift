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
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    guard let stdout = String(data: stdoutData, encoding: .utf8) else {
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
    exec("/usr/local/bin/wat2wasm", [module.path, "-o", output.path] + options)
    return output
}

func wasmObjdump(_ input: URL, args: [String]) -> String {
    exec("/usr/local/bin/wasm-objdump", [input.path] + args)!
}


@testable import WasmTransformer

extension WasmTransformer.InputByteStream {
    init(from url: URL) throws {
        let bytes = try Array(Data(contentsOf: url))
        self.init(bytes: bytes)
    }
}
