public struct InputByteStream {
    public private(set) var offset: Int
    public let bytes: ArraySlice<UInt8>
    public var isEOF: Bool {
        offset >= bytes.endIndex
    }

    public init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.offset = bytes.startIndex
    }

    public init(bytes: [UInt8]) {
        self.init(bytes: bytes[...])
    }

    mutating func readHeader() throws -> ArraySlice<UInt8> {
        let maybeMagic = read(4)
        guard maybeMagic.elementsEqual(magic) else {
            throw Error.badMagic(maybeMagic)
        }
        let version = read(4)
        return version
    }

    mutating func readSectionInfo() throws -> SectionInfo {
        let startOffset = offset
        let rawType = readUInt8()
        guard let type = SectionType(rawValue: rawType) else {
            throw Error.unexpectedSection(rawType)
        }
        let size = Int(readVarUInt32())
        let contentStart = offset

        return .init(
            startOffset: startOffset,
            contentStart: contentStart,
            type: type,
            size: size
        )
    }

    public mutating func seek(_ offset: Int) {
        self.offset = offset
    }

    public mutating func skip(_ length: Int) {
        offset += length
    }

    public mutating func read(_ length: Int) -> ArraySlice<UInt8> {
        let result = bytes[offset ..< offset + length]
        offset += length
        return result
    }

    mutating func readUInt8() -> UInt8 {
        let byte = read(1)
        return byte[byte.startIndex]
    }

    public mutating func readVarUInt32() -> UInt32 {
        let (value, advanced) = decodeULEB128(bytes[offset...], UInt32.self)
        offset += advanced
        return value
    }

    mutating func consumeULEB128<T>(_: T.Type) where T: UnsignedInteger, T: FixedWidthInteger {
        let (_, advanced) = decodeULEB128(bytes[offset...], T.self)
        offset += advanced
    }

    enum Error: Swift.Error {
        case badMagic(ArraySlice<UInt8>)
        case invalidValueType(UInt8)
        case invalidExternalKind(UInt8)
        case unsupportedExternalKind(ExternalKind)
        case expectConstOpcode(UInt8)
        case expectI32Const(ConstOpcode)
        case unexpectedOpcode(UInt8)
        case unexpectedSection(UInt8)
        case expectEnd
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#result-types
    mutating func readResultTypes() throws -> [ValueType] {
        let count = readVarUInt32()
        var resultTypes: [ValueType] = []
        for _ in 0 ..< count {
            let rawType = readUInt8()
            guard let type = ValueType(rawValue: rawType) else {
                throw Error.invalidValueType(rawType)
            }
            resultTypes.append(type)
        }
        return resultTypes
    }

    mutating func readExternalKind() throws -> ExternalKind {
        let rawKind = readUInt8()
        guard let kind = ExternalKind(rawValue: rawKind) else {
            throw Error.invalidExternalKind(rawKind)
        }
        return kind
    }

    typealias Consumer = (ArraySlice<UInt8>) throws -> Void

    mutating func consumeString(consumer: Consumer? = nil) rethrows {
        let start = offset
        let length = Int(readVarUInt32())
        offset += length
        try consumer?(bytes[start ..< offset])
    }

    /// https://webassembly.github.io/spec/core/binary/values.html#names
    mutating func readString() -> String {
        let length = Int(readVarUInt32())
        let strStart = offset
        offset += length
        return String(decoding: bytes[strStart ..< offset], as: UTF8.self)
    }

    mutating func readImportDescriptor() throws -> ImportDescriptor {
        let kind = try readExternalKind()
        switch kind {
        case .func: return .function(readVarUInt32())
        case .table: return .table(rawBytes: consumeTable())
        case .memory: return .memory(rawBytes: consumeMemory())
        case .global: return .global(rawBytes: consumeGlobalHeader())
        case .except: throw Error.unsupportedExternalKind(kind)
        }
    }

    /// https://webassembly.github.io/spec/core/binary/modules.html#import-section
    mutating func readImport() throws -> Import {
        let module = readString()
        let field = readString()
        let desc = try readImportDescriptor()
        return Import(module: module, field: field, descriptor: desc)
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#value-types
    mutating func readFuncType() throws -> FuncSignature {
        let params = try readResultTypes()
        let results = try readResultTypes()
        return FuncSignature(
            params: params, results: results
        )
    }
    /// https://webassembly.github.io/spec/core/binary/types.html#table-types
    mutating func consumeTable() -> ArraySlice<UInt8> {
        let start = offset
        _ = readUInt8() // element type
        let hasMax = readUInt8() != 0
        _ = readVarUInt32() // initial
        if hasMax {
            _ = readVarUInt32() // max
        }
        return bytes[start ..< offset]
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#memory-types
    mutating func consumeMemory() -> ArraySlice<UInt8> {
        let start = offset
        let flags = readUInt8()
        let hasMax = (flags & LIMITS_HAS_MAX_FLAG) != 0
        _ = readVarUInt32() // initial
        if hasMax {
            _ = readVarUInt32() // max
        }
        return bytes[start ..< offset]
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#global-types
    mutating func consumeGlobalHeader() -> ArraySlice<UInt8> {
        let start = offset
        _ = readUInt8() // value type
        _ = readUInt8() // mutable
        return bytes[start ..< offset]
    }

    mutating func consumeI32InitExpr() throws -> ArraySlice<UInt8> {
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
        let opcode = readUInt8()
        guard opcode == END_INST_OPCODE else {
            throw Error.expectEnd
        }
        return bytes[start ..< offset]
    }

    /// https://webassembly.github.io/spec/core/binary/modules.html#binary-local
    @discardableResult
    mutating func consumeLocals(consumer: Consumer? = nil) throws -> UInt32 {
        let start = offset
        let count = readVarUInt32()
        for _ in 0..<count {
            _ = consumeLocal()
        }
        try consumer?(bytes[start ..< offset])
        return count
    }

    mutating func consumeLocal() -> (count: UInt32, rawBytes: ArraySlice<UInt8>) {
        let start = offset
        let count = readVarUInt32() // n
        _ = readUInt8() // value type
        return (count, bytes[start ..< offset])
    }

    mutating func consumeBlockType() {
        let head = bytes[offset]
        let length: Int
        switch head {
        case 0x40:
            length = 1
        case _ where ValueType(rawValue: head) != nil:
            length = 1
        default:
            (_, length) = decodeSLEB128(bytes, Int64.self)
        }
        offset += length
    }

    mutating func consumeBrTable() {
        let count = readVarUInt32()
        for _ in 0 ..< count {
            _ = readVarUInt32()
        }
        _ = readVarUInt32()
    }

    mutating func consumeMemoryArg() {
        _ = readVarUInt32()
        _ = readVarUInt32()
    }

    mutating func consumeInst(code: UInt8) throws {
        switch code {
        // https://webassembly.github.io/spec/core/binary/instructions.html#control-instructions
        case 0x00, 0x01: break
        case 0x02, 0x03, 0x04: consumeBlockType()
        case 0x05, 0x0B: break
        case 0x0C, 0x0D: _ = readVarUInt32() // label index
        case 0x0E: consumeBrTable()
        case 0x0F: break
        case 0x10: _ = readVarUInt32()
        case 0x11:
            _ = readVarUInt32() // type index
            _ = readUInt8() // 0x00

        // https://webassembly.github.io/spec/core/binary/instructions.html#parametric-instructions
        case 0x1A, 0x1B: break

        // https://webassembly.github.io/spec/core/binary/instructions.html#variable-instructions
        case 0x20 ... 0x24: _ = readVarUInt32() // local index

        // https://webassembly.github.io/spec/core/binary/instructions.html#memory-instructions
        case 0x28 ... 0x3E: consumeMemoryArg()
        case 0x3F, 0x40: _ = readUInt8() // 0x00

        // https://webassembly.github.io/spec/core/binary/instructions.html#numeric-instructions
        case 0x41: consumeULEB128(UInt32.self)
        case 0x42: consumeULEB128(UInt64.self)
        case 0x43: _ = read(4)
        case 0x44: _ = read(8)
        case 0x45 ... 0xC4: break
        case 0xFC: _ = readVarUInt32()
        default:
            throw Error.unexpectedOpcode(code)
        }
    }

    mutating func readGlobalSet() throws -> UInt32? {
        let rawCode = readUInt8()
        switch rawCode {
        // https://webassembly.github.io/spec/core/binary/instructions.html#variable-instructions
        case 0x24:
            return readVarUInt32()
        default:
            try consumeInst(code: rawCode)
            return nil
        }
    }

    mutating func readCallInst() throws -> UInt32? {
        let rawCode = readUInt8()
        switch rawCode {
        // https://webassembly.github.io/spec/core/binary/instructions.html#control-instructions
        case 0x10:
            return readVarUInt32()
        default:
            try consumeInst(code: rawCode)
            return nil
        }
    }
}
