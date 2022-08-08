public struct TypeSectionReader: VectorSectionReader {
    enum Error: Swift.Error {
        case unsupportedTypeDefKind(UInt8)
    }

    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> FuncSignature {
        let rawKind = input.readUInt8()
        switch rawKind {
        case 0x60:
            return try input.readFuncType()
        default:
            throw Error.unsupportedTypeDefKind(rawKind)
        }
    }
}
