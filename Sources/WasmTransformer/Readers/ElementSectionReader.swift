struct Element {
    let flags: UInt32
    let items: ElementItemsReader
    let initExpr: ArraySlice<UInt8>
}

struct ElementItemsReader {
    var input: InputByteStream
    let count: UInt32

    mutating func read() -> UInt32 {
        input.readVarUInt32()
    }
}

struct ElementSectionReader {
    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> Element {
        let flags = input.readVarUInt32()
        let initExpr = try input.consumeI32InitExpr()
        let count = input.readVarUInt32()
        return Element(
            flags: flags,
            items: ElementItemsReader(input: input, count: count),
            initExpr: initExpr
        )
    }
}
