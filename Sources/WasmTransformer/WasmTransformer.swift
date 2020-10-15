typealias RawSection = (
    startOffset: Int, endOffset: Int
)


struct TypeSection {
    private(set) var signatures: [FuncSignature] = []

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

public struct I64Transformer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case unexpectedSection(UInt8)
    }
    
    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: Writer) throws {
        let maybeMagic = input.read(4)
        assert(maybeMagic.elementsEqual(magic))
        try writer.writeBytes(magic)
        let maybeVersion = input.read(4)
        assert(maybeVersion.elementsEqual(version))
        try writer.writeBytes(version)

        var importedFunctionCount = 0
        var trampolines = Trampolines()
        do {
            // Phase 1. Scan Type and Import sections to determine import records
            //          which will be lowered.
            var rawSections: [RawSection] = []
            var typeSection = TypeSection()
            var importSection: ImportSection?
            Phase1: while !input.isEOF {
                let offset = input.offset
                let type = input.readUInt8()
                let size = Int(input.readVarUInt32())
                let contentStart = input.offset
                let sectionType = SectionType(rawValue: type)

                switch sectionType {
                case .type:
                    try scan(typeSection: &typeSection, from: &input)
                case .import:
                    let partialStart = input.bytes.startIndex + offset
                    let partialEnd = contentStart + size
                    let partialBytes = input.bytes[partialStart ..< partialEnd]
                    var section = ImportSection(input: InputByteStream(bytes: partialBytes))
                    importedFunctionCount = try scan(
                        importSection: &section, from: &input,
                        typeSection: &typeSection, trampolines: &trampolines
                    )
                    importSection = section
                    break Phase1
                case .custom:
                    rawSections.append((startOffset: offset, endOffset: contentStart + size))
                    input.read(size)
                default:
                    throw Error.unexpectedSection(type)
                }
                assert(input.offset == contentStart + size)
            }

            // Phase 2. Write out Type and Import section based on scanned results.
            try typeSection.write(to: writer)
            if var importSection = importSection {
                try importSection.write(to: writer)
            }

            for rawSection in rawSections {
                try writer.writeBytes(input.bytes[rawSection.startOffset ..< rawSection.endOffset])
            }
        }

        // After here, we can emit binary sequentially

        var originalFuncCount: Int?
        while !input.isEOF {
            let offset = input.offset
            let type = input.readUInt8()
            let size = Int(input.readVarUInt32())
            let contentStart = input.offset
            let sectionType = SectionType(rawValue: type)

            switch sectionType {
            case .type, .import:
                fatalError("unreachable")
            case .function:
                // Phase 3. Write out Func section and add trampoline signatures.
                originalFuncCount = try transformFunctionSection(input: &input, writer: writer, trampolines: trampolines) + importedFunctionCount
            case .elem:
                // Phase 4. Read Elem section and rewrite i64 functions with trampoline functions.
                guard let originalFuncCount = originalFuncCount else {
                    throw Error.expectFunctionSection
                }
                try transformElemSection(
                    input: &input, writer: writer,
                    trampolines: trampolines, originalFuncCount: originalFuncCount
                )
            case .code:
                // Phase 5. Read Code section and rewrite i64 function calls with trampoline function call.
                //          And add trampoline functions at the tail
                guard let originalFuncCount = originalFuncCount else {
                    throw Error.expectFunctionSection
                }
                try transformCodeSection(
                    input: &input, writer: writer,
                    trampolines: trampolines, originalFuncCount: originalFuncCount
                )
            case .custom, .table, .memory, .global, .export, .start, .data, .dataCount:
                // FIXME: Support re-export of imported i64 functions
                try writer.writeBytes(input.bytes[offset ..< contentStart + size])
                input.read(size)
            case .none:
                throw Error.unexpectedSection(type)
            }
            assert(input.offset == contentStart + size)
        }
    }

    /// Returns indices of types that contains i64 in its signature
    func scan(typeSection: inout TypeSection, from input: inout InputByteStream) throws {
        let count = input.readVarUInt32()
        for _ in 0 ..< count {
            assert(input.readUInt8() == 0x60)
            let (params, paramsHasI64) = try input.readResultTypes()
            let (results, resultsHasI64) = try input.readResultTypes()
            let hasI64 = paramsHasI64 || resultsHasI64
            typeSection.append(signature: FuncSignature(params: params, results: results, hasI64: hasI64))
        }
    }

    /// https://webassembly.github.io/spec/core/binary/modules.html#import-section
    /// Returns a count of imported functions
    func scan(importSection: inout ImportSection, from input: inout InputByteStream,
              typeSection: inout TypeSection, trampolines: inout Trampolines) throws -> Int
    {
        let count = input.readVarUInt32()
        var importFuncCount = 0
        for index in 0 ..< count {
            input.consumeString() // module name
            input.consumeString() // field name
            let rawKind = input.readUInt8()
            let kind = ExternalKind(rawValue: rawKind)

            switch kind {
            case .func:
                let signatureIndex = Int(input.readVarUInt32())
                let signature = typeSection.signatures[signatureIndex]
                defer { importFuncCount += 1 }
                guard signature.hasI64 else { continue }

                let toTypeIndex = typeSection.signatures.count
                let toSignature = signature.lowered()
                typeSection.append(signature: toSignature)
                importSection.replacements.append(
                    (index: Int(index), toTypeIndex: toTypeIndex)
                )
                trampolines.add(
                    importIndex: importFuncCount, from: signature,
                    fromIndex: signatureIndex, to: toSignature
                )
            case .table: input.consumeTable()
            case .memory: input.consumeMemory()
            case .global: input.consumeGlobalHeader()
            case .except:
                fatalError("not supported yet")
            case .none:
                throw Error.invalidExternalKind(rawKind)
            }
        }
        return importFuncCount
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

func transformCodeSection(input: inout InputByteStream, writer: OutputWriter,
                          trampolines: Trampolines, originalFuncCount: Int) throws
{
    try writeSection(.code, writer: writer) { writer in
        let count = Int(input.readVarUInt32())
        let newCount = count + trampolines.count
        try writer.writeBytes(encodeULEB128(UInt32(newCount)))
        for _ in 0 ..< count {
            let oldSize = Int(input.readVarUInt32())
            let bodyEnd = input.offset + oldSize
            var bodyBuffer: [UInt8] = []
            bodyBuffer.reserveCapacity(oldSize)

            try input.consumeLocals(consumer: {
                bodyBuffer.append(contentsOf: $0)
            })

            while input.offset < bodyEnd {
                let opcode = try input.readOpcode()
                guard case let .call(funcIndex) = opcode,
                    let (_, trampolineIndex) = trampolines.trampoline(byBaseFuncIndex: Int(funcIndex))
                else {
                    bodyBuffer.append(contentsOf: opcode.serialize())
                    continue
                }
                let newTargetIndex = originalFuncCount + trampolineIndex
                let callInst = Opcode.call(UInt32(newTargetIndex))
                bodyBuffer.append(contentsOf: callInst.serialize())
            }
            let newSize = bodyBuffer.count
            try writer.writeBytes(encodeULEB128(UInt32(newSize)))
            try writer.writeBytes(bodyBuffer)
        }

        for trampoline in trampolines {
            try trampoline.write(to: writer)
        }
    }
}

/// Read Elem section and rewrite i64 functions with trampoline functions.
func transformElemSection(input: inout InputByteStream, writer: OutputWriter,
                          trampolines: Trampolines, originalFuncCount: Int) throws
{
    try writeSection(.elem, writer: writer) { writer in
        let count = input.readVarUInt32()
        try writer.writeBytes(encodeULEB128(UInt32(count)))
        for _ in 0 ..< count {
            let tableIndex = input.readVarUInt32()
            try writer.writeBytes(encodeULEB128(tableIndex))
            try input.consumeI32InitExpr(consumer: writer.writeBytes)
            let funcIndicesCount = input.readVarUInt32()
            try writer.writeBytes(encodeULEB128(funcIndicesCount))
            for _ in 0 ..< funcIndicesCount {
                let funcIndex = input.readVarUInt32()
                if let (_, index) = trampolines.trampoline(byBaseFuncIndex: Int(funcIndex)) {
                    try writer.writeBytes(encodeULEB128(UInt32(index + originalFuncCount)))
                } else {
                    try writer.writeBytes(encodeULEB128(funcIndex))
                }
            }
        }
    }
}

/// Write out Func section and add trampoline signatures.
func transformFunctionSection(input: inout InputByteStream, writer: OutputWriter, trampolines: Trampolines) throws -> Int {
    try writeSection(.function, writer: writer) { writer in
        let count = Int(input.readVarUInt32())
        let newCount = count + trampolines.count
        try writer.writeBytes(encodeULEB128(UInt32(newCount)))

        for _ in 0 ..< count {
            let typeIndex = input.readVarUInt32()
            try writer.writeBytes(encodeULEB128(typeIndex))
        }

        for trampoline in trampolines {
            let index = UInt32(trampoline.fromSignatureIndex)
            try writer.writeBytes(encodeULEB128(index))
        }
        return count
    }
}
