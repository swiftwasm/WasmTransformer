public struct FunctionBody {
    var input: InputByteStream
    let size: UInt32
    let endOffset: Int

    func locals() -> LocalsReader {
        LocalsReader(input: input)
    }
}

struct LocalsReader {
    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> (count: UInt32, rawBytes: ArraySlice<UInt8>) {
        input.consumeLocal()
    }

    func operators() -> InputByteStream {
        input
    }
}

public struct CodeSectionReader: VectorSectionReader {
    var input: InputByteStream
    public let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    public mutating func read() throws -> FunctionBody {
        let size = input.readVarUInt32()
        let body = FunctionBody(input: input, size: size,
                                endOffset: input.offset + Int(size))
        input.skip(Int(size))
        return body
    }
}
