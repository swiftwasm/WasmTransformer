
public struct StackOverflowSanitizer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case supportLibraryNotLinked
        case expectTypeSection
        case invalidFunctionIndex
        case invalidTypeIndex
    }

    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)
        var reportFuncIndex: UInt32?
        var typeSection: [FuncSignature]?
        var funcSection: [SignatureIndex]?

        while !input.isEOF {
            let sectionInfo = try input.readSectionInfo()

            switch sectionInfo.type {
            case .type:
                let reader = TypeSectionReader(input: input)
                typeSection = try reader.collect()
                try writer.writeBytes(
                    input.bytes[sectionInfo.startOffset ..< sectionInfo.endOffset]
                )
            case .function:
                let reader = FunctionSectionReader(input: input)
                funcSection = try reader.collect()
                try writer.writeBytes(
                    input.bytes[sectionInfo.startOffset ..< sectionInfo.endOffset]
                )
            case .import:
                let reader = ImportSectionReader(input: input)
                let entries = try reader.lazy.map { try $0.get() }
                    .filter {
                        guard case .function(_) = $0.descriptor else { return false }
                        return true
                    }
                reportFuncIndex = entries.firstIndex(where: {
                    return $0.module == "__stack_sanitizer" && $0.field == "report_stack_overflow"
                })
                .map(UInt32.init)

                try writer.writeBytes(
                    input.bytes[sectionInfo.startOffset ..< sectionInfo.endOffset]
                )
            case .code:
                guard let reportFuncIndex = reportFuncIndex else {
                    throw Error.supportLibraryNotLinked
                }
                guard let typeSection = typeSection else {
                    throw Error.expectTypeSection
                }
                guard let funcSection = funcSection else {
                    throw Error.expectFunctionSection
                }
                var reader = CodeSectionReader(input: input)
                try transformCodeSection(
                    input: &reader, writer: &writer,
                    reportFuncIndex: reportFuncIndex,
                    typeSection: typeSection, funcSection: funcSection
                )
            default:
                try writer.writeBytes(
                    input.bytes[sectionInfo.startOffset ..< sectionInfo.endOffset]
                )
            }
            input.skip(sectionInfo.size)
        }
    }

    func transformCodeSection<Writer: OutputWriter>(
        input: inout CodeSectionReader,
        writer: inout Writer,
        reportFuncIndex: UInt32,
        typeSection: [FuncSignature],
        funcSection: [SignatureIndex]
    ) throws {
        try writer.writeVectorSection(type: .code, count: input.count) { writer in
            for index in 0 ..< input.count {
                let body = try input.read()
                guard index < funcSection.count else {
                    throw Error.invalidFunctionIndex
                }
                let sigIndex = funcSection[Int(index)]
                guard sigIndex.value < typeSection.count else {
                    throw Error.invalidTypeIndex
                }
                try transformFunction(
                    input: body, writer: writer,
                    reportFuncIndex: reportFuncIndex,
                    signature: typeSection[Int(sigIndex.value)]
                )
            }
        }
    }

    func transformFunction(input: FunctionBody, writer: OutputWriter,
                           reportFuncIndex: UInt32,
                           signature: FuncSignature) throws {
        let oldSize = Int(input.size)
        var bodyBuffer: [UInt8] = []
        bodyBuffer.reserveCapacity(oldSize)

        var locals = input.locals()
        var spLocalIdx = UInt32(signature.params.count)

        bodyBuffer.append(contentsOf: encodeULEB128(locals.count + 1))
        for _ in 0 ..< locals.count {
            let (count, bytes) = try locals.read()
            spLocalIdx += count
            bodyBuffer.append(contentsOf: bytes)
        }
        // Add extra "local" to restore stack-pointer
        bodyBuffer.append(
            contentsOf: encodeULEB128(UInt32(1)) + [ValueType.i32.rawValue]
        )

        var operators = locals.operators()
        var lazyChunkStart = operators.offset
        while operators.offset < input.endOffset {
            let lazyChunkEnd = operators.offset
            let rawCode = operators.readUInt8()
            func flushLazyChunk() {
                bodyBuffer.append(contentsOf: operators.bytes[lazyChunkStart..<lazyChunkEnd])
                lazyChunkStart = operators.offset
            }
            switch rawCode {
            case 0x24: // global.set
                let globalIndex = operators.readVarUInt32()
                guard globalIndex == 0 else { continue }
                flushLazyChunk()
                let opcodes = [
                    Opcode.localSet(spLocalIdx),
                    Opcode.localGet(spLocalIdx),
                    Opcode.i32Const(0),
                    Opcode.i32LtS,
                    Opcode.if(.empty),
                    Opcode.call(reportFuncIndex),
                    Opcode.end,
                    Opcode.localGet(spLocalIdx),
                    Opcode.globalSet(0),
                ]
                bodyBuffer.append(contentsOf: opcodes.flatMap { $0.serialize() })
            default:
                try operators.consumeInst(code: rawCode)
                continue
            }
        }
        bodyBuffer.append(contentsOf: operators.bytes[lazyChunkStart..<operators.offset])
        try writer.writeBytes(encodeULEB128(UInt32(bodyBuffer.count)))
        try writer.writeBytes(bodyBuffer)
    }



}

