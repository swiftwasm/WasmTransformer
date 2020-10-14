struct InputStream {
    private(set) var offset: Int = 0
    let bytes: ArraySlice<UInt8>
    let length: Int
    var isEOF: Bool {
        offset >= length
    }

    init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        length = bytes.count
    }
    init(bytes: [UInt8]) {
        self.init(bytes: bytes[...])
    }

    @discardableResult
    mutating func read(_ length: Int) -> ArraySlice<UInt8> {
        let result = bytes[offset ..< offset + length]
        offset += length
        return result
    }

    mutating func readUInt8() -> UInt8 {
        let byte = read(1)
        return byte[byte.startIndex]
    }

    mutating func readVarUInt32() -> UInt32 {
        let (value, advanced) = decodeLEB128(bytes[offset...])
        offset += advanced
        return value
    }

    mutating func readUInt32() -> UInt32 {
        let bytes = read(4)
        return UInt32(bytes[bytes.startIndex + 0])
            + (UInt32(bytes[bytes.startIndex + 1]) << 8)
            + (UInt32(bytes[bytes.startIndex + 2]) << 16)
            + (UInt32(bytes[bytes.startIndex + 3]) << 24)
    }

    mutating func readString() -> String {
        let length = Int(readVarUInt32())
        let bytes = self.bytes[offset ..< offset + length]
        let name = String(decoding: bytes, as: Unicode.ASCII.self)
        offset += length
        return name
    }

    
    typealias Consumer = (ArraySlice<UInt8>) throws -> Void

    mutating func consumeString(consumer: Consumer? = nil) rethrows {
        let start = offset
        let length = Int(readVarUInt32())
        offset += length
        try consumer?(bytes[start..<offset])
    }
    
    /// https://webassembly.github.io/spec/core/binary/types.html#table-types
    mutating func consumeTable(consumer: Consumer? = nil) rethrows {
        let start = offset
        _ = readUInt8() // element type
        let hasMax = readUInt8() != 0
        _ = readVarUInt32() // initial
        if hasMax {
            _ = readVarUInt32() // max
        }
        try consumer?(bytes[start..<offset])
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#memory-types
    mutating func consumeMemory(consumer: Consumer? = nil) rethrows {
        let start = offset
        let flags = readUInt8()
        let hasMax = (flags & LIMITS_HAS_MAX_FLAG) != 0
        _ = readVarUInt32() // initial
        if hasMax {
            _ = readVarUInt32() // max
        }
        try consumer?(bytes[start..<offset])
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#global-types
    mutating func consumeGlobalHeader(consumer: Consumer? = nil) rethrows {
        let start = offset
        _ = readUInt8() // value type
        _ = readUInt8() // mutable
        try consumer?(bytes[start..<offset])
    }
    
    enum Error: Swift.Error {
        case expectConstOpcode(UInt8)
        case expectI32Const(ConstOpcode)
        case expectEnd
    }

    mutating func consumeI32InitExpr(consumer: Consumer? = nil) throws {
        let start = offset
        let code = readUInt8()
        guard let constOp = ConstOpcode(rawValue: code) else {
            throw Error.expectConstOpcode(code)
        }
        switch constOp {
        case .i32Const:
            _ = readVarUInt32()
        case .f32Const, .f64Const, .i64Const:
            throw Error.expectI32Const(constOp)
        }
        let endCode = readUInt8()
        guard let opcode = Opcode(rawValue: endCode),
            opcode == .end
        else {
            throw Error.expectEnd
        }
        try consumer?(bytes[start..<offset])
    }
}
