public struct SectionInfo: Equatable {
    public let startOffset: Int
    public let endOffset: Int
    public let type: SectionType
    public let size: Int
}

public struct TypeSection {
    public private(set) var signatures: [FuncSignature] = []

    init() {}

    public init(from input: inout InputByteStream) throws {
        let count = input.readVarUInt32()
        for _ in 0 ..< count {
            let header = input.readUInt8()
            assert(header == 0x60)
            let (params, paramsHasI64) = try input.readResultTypes()
            let (results, resultsHasI64) = try input.readResultTypes()
            let hasI64 = paramsHasI64 || resultsHasI64
            signatures.append(FuncSignature(params: params, results: results, hasI64: hasI64))
        }
    }

    func write<Writer: OutputWriter>(to writer: Writer) throws {
        try writeSection(.type, writer: writer) { buffer in
            try buffer.writeBytes(encodeULEB128(UInt32(signatures.count)))
            for signature in signatures {
                try buffer.writeByte(0x60)
                try writeResultTypes(signature.params, to: buffer)
                try writeResultTypes(signature.results, to: buffer)
            }
        }
    }
    
    mutating func append(signature: FuncSignature) {
        signatures.append(signature)
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#result-types
    func writeResultTypes(_ types: [ValueType], to writer: OutputWriter) throws {
        try writer.writeBytes(encodeULEB128(UInt32(types.count)))
        for type in types {
            try writer.writeByte(type.rawValue)
        }
    }
}

typealias ImportFuncReplacement = (index: Int, toTypeIndex: Int)

struct ImportSection {
    var input: InputByteStream
    var replacements: [ImportFuncReplacement] = []

    mutating func write<Writer: OutputWriter>(to writer: Writer) throws {
        let sectionType = input.readUInt8()
        assert(SectionType(rawValue: sectionType) == .import)
        try writer.writeByte(sectionType)

        let oldContentSize = input.readVarUInt32()
        let contentBuffer = InMemoryOutputWriter(reservingCapacity: Int(oldContentSize))

        let count = input.readVarUInt32()
        try contentBuffer.writeBytes(encodeULEB128(count))
        for index in 0 ..< count {
            try input.consumeString(consumer: contentBuffer.writeBytes) // module name
            try input.consumeString(consumer: contentBuffer.writeBytes) // field name
            let rawKind = input.readUInt8()
            try contentBuffer.writeByte(rawKind)
            let kind = ExternalKind(rawValue: rawKind)

            switch kind {
            case .func:
                let oldSignatureIndex = input.readVarUInt32()
                let newSignatureIndex: UInt32
                if let replacement = replacements.first(where: { $0.index == index }) {
                    newSignatureIndex = UInt32(replacement.toTypeIndex)
                } else {
                    newSignatureIndex = oldSignatureIndex
                }
                try contentBuffer.writeBytes(encodeULEB128(newSignatureIndex))
            case .table:  try input.consumeTable(consumer: contentBuffer.writeBytes)
            case .memory: try input.consumeMemory(consumer: contentBuffer.writeBytes)
            case .global: try input.consumeGlobalHeader(consumer: contentBuffer.writeBytes)
            case .except:
                fatalError("not supported yet")
            case .none:
                fatalError()
            }
        }
        
        try writer.writeBytes(encodeULEB128(UInt32(contentBuffer.bytes().count)))
        try writer.writeBytes(contentBuffer.bytes())
    }
}

func writeSection<T>(_ type: SectionType, writer: OutputWriter, bodyWriter: (OutputWriter) throws -> T) throws -> T {
    try writer.writeByte(type.rawValue)
    let buffer = InMemoryOutputWriter()
    let result = try bodyWriter(buffer)
    try writer.writeBytes(encodeULEB128(UInt32(buffer.bytes().count)))
    try writer.writeBytes(buffer.bytes())
    return result
}
