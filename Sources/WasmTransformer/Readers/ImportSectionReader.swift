struct Import {
    let module: String
    let field: String
    let descriptor: ImportDescriptor
}

enum ImportDescriptor {
    case function(UInt32)
    case table(rawBytes:  ArraySlice<UInt8>)
    case memory(rawBytes: ArraySlice<UInt8>)
    case global(rawBytes: ArraySlice<UInt8>)
}

struct ImportSectionReader {
    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> Import {
        try input.readImport()
    }
}
