public struct TypeSectionReader: VectorSectionReader {
    enum Error: Swift.Error {
        case unsupportedTypeDefKind(UInt8)
    }

    var input: InputByteStream
    public let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        count = self.input.readVarUInt32()
    }

    public mutating func read() throws -> FuncSignature {
        let rawKind = input.readUInt8()
        switch rawKind {
        case 0x60:
            return try input.readFuncType()
        default:
            throw Error.unsupportedTypeDefKind(rawKind)
        }
    }
}
