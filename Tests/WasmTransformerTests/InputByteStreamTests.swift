@testable import WasmTransformer
import XCTest

final class InputByteStreamTests: XCTestCase {
    let buildPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/build")

    func testReadCallInst() {
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            var input = try! InputByteStream(from: buildPath.appendingPathComponent("main.wasm"))
            input.readHeader()
            readUntilCode: while !input.isEOF {
                let sectionInfo = try! input.readSectionInfo()
                let contentStart = sectionInfo.endOffset - sectionInfo.size

                switch sectionInfo.type {
                case .code:
                    break readUntilCode
                default:
                    input.skip(sectionInfo.size)
                }
                assert(input.offset == contentStart + sectionInfo.size)
            }

            let count = Int(input.readVarUInt32())
            self.startMeasuring()
            for _ in 0 ..< count {
                let oldSize = Int(input.readVarUInt32())
                let bodyEnd = input.offset + oldSize
                var bodyBuffer: [UInt8] = []
                bodyBuffer.reserveCapacity(oldSize)

                try! input.consumeLocals(consumer: {
                    bodyBuffer.append(contentsOf: $0)
                })

                while input.offset < bodyEnd {
                    _ = try! input.readCallInst()
                }
            }
            self.stopMeasuring()
        }
    }
}
