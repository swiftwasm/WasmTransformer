public struct Import {
    public var module: String
    public var field: String
    public var descriptor: ImportDescriptor
}

public enum ImportDescriptor {
    case function(UInt32)
    case table(rawBytes:  ArraySlice<UInt8>)
    case memory(rawBytes: ArraySlice<UInt8>)
    case global(rawBytes: ArraySlice<UInt8>)
}

public struct ImportSectionReader: VectorSectionReader {
    var input: InputByteStream
    public let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    public mutating func read() throws -> Import {
        try input.readImport()
    }
}
