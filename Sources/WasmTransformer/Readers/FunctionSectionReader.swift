public struct SignatureIndex: Equatable {
    let value: UInt32
}

public struct FunctionSectionReader: VectorSectionReader {
    var input: InputByteStream
    public let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    public mutating func read() throws -> SignatureIndex {
        return SignatureIndex(value: input.readVarUInt32())
    }
}
