struct ElementSegment {
    let flags: UInt32
    let initExpr: ArraySlice<UInt8>
    var items: ElementItemsReader
}

struct FunctionIndex: Equatable {
    let value: UInt32
}

struct ElementItemsReader {
    var input: InputByteStream
    let count: UInt32

    mutating func read() -> FunctionIndex {
        FunctionIndex(value: input.readVarUInt32())
    }
}

public struct ElementSectionReader: VectorSectionReader {
    var input: InputByteStream
    let count: UInt32

    init(input: InputByteStream) {
        self.input = input
        self.count = self.input.readVarUInt32()
    }

    mutating func read() throws -> ElementSegment {
        let flags = input.readVarUInt32()
        let initExpr = try input.consumeI32InitExpr()
        let count = input.readVarUInt32()
        return ElementSegment(
            flags: flags,
            initExpr: initExpr,
            items: ElementItemsReader(input: input, count: count)
        )
    }
}
