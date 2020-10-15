struct Trampoline {
    let fromSignature: FuncSignature
    let toSignature: FuncSignature
    let fromSignatureIndex: Int
    let originalFuncIndex: Int

    func write(to writer: OutputWriter) throws {
        var bodyBuffer: [UInt8] = []
        bodyBuffer.append(0x00) // local decl count

        for (index, param) in fromSignature.params.enumerated() {
            bodyBuffer.append(contentsOf: Opcode.localGet(UInt32(index)).serialize())
            if param == .i64 {
                bodyBuffer.append(contentsOf: Opcode.i32WrapI64.serialize())
            }
        }

        bodyBuffer.append(contentsOf: Opcode.call(UInt32(originalFuncIndex)).serialize())
        bodyBuffer.append(contentsOf: Opcode.end.serialize())

        try writer.writeBytes(encodeULEB128(UInt32(bodyBuffer.count)))
        try writer.writeBytes(bodyBuffer)
    }
}

struct Trampolines: Sequence {
    private var trampolineByBaseFuncIndex: [Int: (Trampoline, index: Int)] = [:]
    private var trampolines: [Trampoline] = []
    var count: Int { trampolineByBaseFuncIndex.count }

    mutating func add(importIndex: Int, from: FuncSignature, fromIndex: Int, to: FuncSignature) {
        let trampoline = Trampoline(fromSignature: from,
                                    toSignature: to, fromSignatureIndex: fromIndex,
                                    originalFuncIndex: importIndex)
        trampolineByBaseFuncIndex[importIndex] = (trampoline, trampolines.count)
        trampolines.append(trampoline)
    }

    func trampoline(byBaseFuncIndex index: Int) -> (Trampoline, Int)? {
        trampolineByBaseFuncIndex[index]
    }

    typealias Iterator = Array<Trampoline>.Iterator
    func makeIterator() -> Iterator {
        trampolines.makeIterator()
    }
}
