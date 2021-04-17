
public struct StackOverflowSanitizer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case invalidSectionOrder
    }

    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)
        var reportFuncIndex: UInt32?
        var existingImportCount: UInt32?
        var isImportFlushed = false

        while !input.isEOF {
            let sectionInfo = try input.readSectionInfo()

            var importReader: ImportSectionReader?
            var typeCount: UInt32 = 0

            if !isImportFlushed, sectionInfo.type.rawValue > SectionType.import.rawValue {
                isImportFlushed = true
                let reportFunction = Import(
                    module: "__stack_sanitizer", field: "report_stack_overflow",
                    descriptor: .function(typeCount)
                )
                if let importReader = importReader {
                    try writer.writeVectorSection(type: .import, reader: importReader,
                                                  extras: [reportFunction])
                    reportFuncIndex = importReader.count
                    existingImportCount = importReader.count
                } else {
                    try writer.writeVectorSection(type: .import, items: [reportFunction])
                    reportFuncIndex = 0
                    existingImportCount = 0
                }
            }

            switch sectionInfo.type {
            case .type:
                let reader = TypeSectionReader(input: input)
                typeCount = reader.count
            case .import:
                importReader = ImportSectionReader(input: input)
            case .code:
                guard let reportFuncIndex = reportFuncIndex,
                      let existingImportCount = existingImportCount else {
                    throw Error.invalidSectionOrder
                }
                var reader = CodeSectionReader(input: input)
                try transformCodeSection(
                    input: &reader, writer: &writer,
                    reportFuncIndex: reportFuncIndex,
                    existingImportCount: existingImportCount,
                    extraImportCount: 1
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
        existingImportCount: UInt32,
        extraImportCount: UInt32
    ) throws {
        try writer.writeVectorSection(type: .code, count: input.count) { writer in
            for _ in 0 ..< input.count {
                let body = try input.read()
                try transformFunction(
                    input: body, writer: writer,
                    reportFuncIndex: reportFuncIndex,
                    existingImportCount: existingImportCount,
                    extraImportCount: extraImportCount
                )
            }
        }
    }

    func transformFunction(input: FunctionBody, writer: OutputWriter,
                           reportFuncIndex: UInt32,
                           existingImportCount: UInt32,
                           extraImportCount: UInt32) throws {
        let oldSize = Int(input.size)
        var bodyBuffer: [UInt8] = []
        bodyBuffer.reserveCapacity(oldSize)

        var locals = input.locals()
        let spLocalIdx = locals.count

        bodyBuffer.append(contentsOf: encodeULEB128(locals.count + 1))
        for _ in 0 ..< locals.count {
            try bodyBuffer.append(contentsOf: locals.read())
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
            case 0x10: // call
                let funcIndex = operators.readVarUInt32()
                flushLazyChunk()
                guard funcIndex >= existingImportCount else {
                    continue
                }
                let call = Opcode.call(funcIndex + extraImportCount)
                bodyBuffer.append(contentsOf: call.serialize())
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
                ]
                bodyBuffer.append(contentsOf: opcodes.flatMap { $0.serialize() })
            default:
                try operators.consumeInst(code: rawCode)
                continue
            }
            guard let globalIndex = try operators.readGlobalSet(), globalIndex == 0 else {
                continue
            }
        }
        try writer.writeBytes(encodeULEB128(UInt32(bodyBuffer.count)))
        try writer.writeBytes(bodyBuffer)
    }



}

