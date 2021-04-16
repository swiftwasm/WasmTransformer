public struct I64ImportTransformer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case unexpectedSection(UInt8)
    }
    
    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: Writer) throws {
        input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)

        var importedFunctionCount = 0
        var trampolines = Trampolines()
        do {
            // Phase 1. Scan Type and Import sections to determine import records
            //          which will be lowered.
            var sections: [SectionInfo] = []
            var typeSection = TypeSection()
            var importSection: ImportSection?
            Phase1: while !input.isEOF {
                let sectionInfo = try input.readSectionInfo()

                switch sectionInfo.type {
                case .type:
                    typeSection = try TypeSection(from: &input)
                case .import:
                    let partialStart = input.bytes.startIndex + sectionInfo.startOffset
                    let partialEnd = sectionInfo.contentStart + sectionInfo.size
                    let partialBytes = input.bytes[partialStart ..< partialEnd]
                    var section = ImportSection(input: InputByteStream(bytes: partialBytes))
                    importedFunctionCount = try scan(
                        importSection: &section, from: &input,
                        typeSection: &typeSection, trampolines: &trampolines
                    )
                    importSection = section
                    break Phase1
                case .custom:
                    sections.append(sectionInfo)
                    input.skip(sectionInfo.size)
                default:
                    throw Error.unexpectedSection(sectionInfo.type.rawValue)
                }
                assert(input.offset == sectionInfo.endOffset)
            }

            // Phase 2. Write out Type and Import section based on scanned results.
            try typeSection.write(to: writer)
            if var importSection = importSection {
                try importSection.write(to: writer)
            }

            for section in sections {
                try writer.writeBytes(input.bytes[section.startOffset ..< section.endOffset])
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
                input.skip(size)
            case .none:
                throw Error.unexpectedSection(type)
            }
            assert(input.offset == contentStart + size)
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

private func transformCodeSection(input: inout InputByteStream, writer: OutputWriter,
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

            var nonCallInstStart = input.offset
            while input.offset < bodyEnd {
                guard let (funcIndex, instSize) = try input.readCallInst(),
                    let (_, trampolineIndex) = trampolines.trampoline(byBaseFuncIndex: Int(funcIndex))
                else {
                    continue
                }
                let nonCallInstEnd = input.offset - instSize
                bodyBuffer.append(contentsOf: input.bytes[nonCallInstStart..<nonCallInstEnd])
                nonCallInstStart = input.offset
                let newTargetIndex = originalFuncCount + trampolineIndex
                let callInst = Opcode.call(UInt32(newTargetIndex))
                bodyBuffer.append(contentsOf: callInst.serialize())
            }
            bodyBuffer.append(contentsOf: input.bytes[nonCallInstStart..<input.offset])
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
private func transformElemSection(input: inout InputByteStream, writer: OutputWriter,
                          trampolines: Trampolines, originalFuncCount: Int) throws
{
    try writeSection(.elem, writer: writer) { writer in
        let count = input.readVarUInt32()
        try writer.writeBytes(encodeULEB128(UInt32(count)))
        for _ in 0 ..< count {
            let tableIndex = input.readVarUInt32()
            try writer.writeBytes(encodeULEB128(tableIndex))
            try input.consumeI32InitExpr(consumer: { try writer.writeBytes($0) })
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
private func transformFunctionSection(input: inout InputByteStream, writer: OutputWriter, trampolines: Trampolines) throws -> Int {
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
