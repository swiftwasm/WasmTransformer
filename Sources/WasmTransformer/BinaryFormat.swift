let magic: [UInt8] = [0x00, 0x61, 0x73, 0x6D]
let version: [UInt8] = [0x01, 0x00, 0x00, 0x00]

let LIMITS_HAS_MAX_FLAG: UInt8 = 0x1
let LIMITS_IS_SHARED_FLAG: UInt8 = 0x2

public enum SectionType: UInt8 {
    case custom = 0
    case type = 1
    case `import` = 2
    case function = 3
    case table = 4
    case memory = 5
    case global = 6
    case export = 7
    case start = 8
    case elem = 9
    case code = 10
    case data = 11
    case dataCount = 12
}

public enum ValueType: UInt8, Equatable {
    case i32 = 0x7F
    case i64 = 0x7E
    case f32 = 0x7D
    case f64 = 0x7C
}

enum ExternalKind: UInt8, Equatable {
    case `func` = 0
    case table = 1
    case memory = 2
    case global = 3
    case except = 4
}

enum ConstOpcode: UInt8 {
    case i32Const = 0x41
    case i64Const = 0x42
    case f32Const = 0x43
    case f64Const = 0x44
}


enum BlockType {
    case empty
}

let END_INST_OPCODE: UInt8 = 0x0B
enum Opcode: Equatable {
    case unreachable
    case end
    case localGet(UInt32)
    case localSet(UInt32)
    case globalSet(UInt32)
    case `if`(BlockType)
    case call(UInt32)
    case i32Const(Int32)
    case i32LtS
    case i32WrapI64
    case unknown([UInt8])

    func serialize() -> [UInt8] {
        switch self {
        case .unreachable: return [0x00]
        case .end: return [END_INST_OPCODE]
        case let .localGet(localIndex):
            return [0x20] + encodeULEB128(localIndex)
        case let .localSet(localIndex):
            return [0x21] + encodeULEB128(localIndex)
        case let .globalSet(globalIndex):
            return [0x24] + encodeULEB128(globalIndex)
        case .if(.empty):
            return [0x04, 0x40]
        case let .call(funcIndex):
            return [0x10] + encodeULEB128(funcIndex)
        case let .i32Const(value):
            return [0x41] + encodeSLEB128(value)
        case .i32LtS: return [0x48]
        case .i32WrapI64: return [0xA7]
        case let .unknown(bytes): return bytes
        }
    }
}

public struct FuncSignature {
    public let params: [ValueType]
    public let results: [ValueType]
}
