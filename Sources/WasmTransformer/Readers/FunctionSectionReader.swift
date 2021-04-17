struct FunctionSectionReader {
    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> UInt32 {
        return input.readVarUInt32()
    }
}
