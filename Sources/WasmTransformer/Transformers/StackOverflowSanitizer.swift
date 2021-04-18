
public struct StackOverflowSanitizer {
    enum Error: Swift.Error {
        case expectFunctionSection
        case supportLibraryNotLinked
        case expectTypeSection
        case invalidFunctionIndex
        case invalidTypeIndex
    }

    public init() {}

    /// This hardcoded byte array is produced from the following wat file with hand-assembled "linking" section.
    /// The dummy function is defined to avoid unused-import elimination.
    /// This object file is required to embed the import entry and the entry will be used while assertion.
    /// ```
    /// (module
    ///   (type (;0;) (func (param i32) (result i32)))
    ///   (type (;1;) (func))
    ///   (import "__stack_sanitizer" "report_stack_overflow" (func (;0;) (type 0)))
    ///   (func (;1;) (type 1)
    ///     i32.const 0
    ///     call 0
    ///     return))
    /// ```
    public static let supportObjectFile: [UInt8] = [
        // magic
        0x00, 0x61, 0x73, 0x6d,
        // version
        0x01, 0x00, 0x00, 0x00,
        // type section
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        // import section
        0x02, 0x2b, 0x01, 0x11, 0x5f, 0x5f, 0x73, 0x74, 0x61, 0x63, 0x6b, 0x5f, 0x73, 0x61, 0x6e, 0x69,
        0x74, 0x69, 0x7a, 0x65, 0x72, 0x15, 0x72, 0x65, 0x70, 0x6f, 0x72, 0x74, 0x5f, 0x73, 0x74, 0x61,
        0x63, 0x6b, 0x5f, 0x6f, 0x76, 0x65, 0x72, 0x66, 0x6c, 0x6f, 0x77, 0x00, 0x00,
        // function section
        0x03, 0x02, 0x01, 0x00,
        // code section
        0x0a, 0x09, 0x01, 0x07, 0x00, 0x41, 0x00, 0x10, 0x00, 0x0f, 0x0b,
        // Custom Section "linking"
        0x00, 0x37, 0x07, 0x6c, 0x69, 0x6e, 0x6b, 0x69, 0x6e, 0x67, 0x02,
        // symbol table
        0x08, 0x2c, 0x01, 0x00, 0x50, 0x00,
        0x27, 0x5f, 0x5f, 0x73, 0x74, 0x61, 0x63, 0x6b, 0x5f, 0x73, 0x61, 0x6e, 0x69, 0x74,
        0x69, 0x7a, 0x65, 0x72,
        0x5f, 0x72, 0x65, 0x70, 0x6f, 0x72, 0x74, 0x5f, 0x73, 0x74, 0x61, 0x63, 0x6b, 0x5f, 0x6f, 0x76,
        0x65, 0x72, 0x66, 0x6c, 0x6f, 0x77,
    ]

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)
        var importCount: UInt32?
        var reportFuncIndex: UInt32?
        var assertSigIndex: UInt32?
        var assertFuncIndex: UInt32?

        while !input.isEOF {
            let sectionInfo = try input.readSectionInfo()

            switch sectionInfo.type {
            case .type:
                let reader = TypeSectionReader(input: input)
                assertSigIndex = reader.count
                let assertSignature = FuncSignature(
                    params: [.i32], results: [.i32], hasI64: false
                )
                try writer.writeVectorSection(
                    type: .type, reader: reader, extras: [assertSignature]
                )
            case .import:
                let reader = ImportSectionReader(input: input)
                importCount = reader.count
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
            case .function:
                let reader = FunctionSectionReader(input: input)
                assertFuncIndex = (importCount ?? 0) + reader.count
                guard let assertSigIndex = assertSigIndex else {
                    throw Error.expectTypeSection
                }
                try writer.writeVectorSection(
                    type: .function, reader: reader, extras: [
                        SignatureIndex(value: assertSigIndex)
                    ]
                )
            case .code:
                guard let reportFuncIndex = reportFuncIndex else {
                    throw Error.supportLibraryNotLinked
                }
                guard let assertFuncIndex = assertFuncIndex else {
                    throw Error.expectFunctionSection
                }
                var reader = CodeSectionReader(input: input)
                try transformCodeSection(
                    input: &reader, writer: &writer,
                    reportFuncIndex: reportFuncIndex,
                    assertFuncIndex: assertFuncIndex
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
        assertFuncIndex: UInt32
    ) throws {
        try writer.writeVectorSection(type: .code, count: input.count + 1) { writer in
            for _ in 0 ..< input.count {
                let body = try input.read()
                try transformFunction(
                    input: body, writer: writer,
                    assertFuncIndex: assertFuncIndex
                )
            }
            try emitStackPointerAssert(reportFuncIndex: reportFuncIndex, writer: writer)
        }
    }

    func emitStackPointerAssert(reportFuncIndex: UInt32, writer: OutputWriter) throws {
        var bodyBuffer: [UInt8] = []
        bodyBuffer.append(0x00) // local decl count
        let opcode = [
            Opcode.localGet(0),
            Opcode.i32Const(0),
            Opcode.i32LtS,
            Opcode.if(.empty),
            Opcode.call(reportFuncIndex),
            Opcode.end,
            Opcode.localGet(0),
            Opcode.end,
        ]
        bodyBuffer.append(contentsOf: opcode.flatMap { $0.serialize() })
        try writer.writeBytes(encodeULEB128(UInt32(bodyBuffer.count)))
        try writer.writeBytes(bodyBuffer)
    }

    func transformFunction(input: FunctionBody, writer: OutputWriter,
                           assertFuncIndex: UInt32) throws {
        let oldSize = Int(input.size)
        var bodyBuffer: [UInt8] = []
        bodyBuffer.reserveCapacity(oldSize)

        var locals = input.locals()

        bodyBuffer.append(contentsOf: encodeULEB128(locals.count))
        for _ in 0 ..< locals.count {
            try bodyBuffer.append(contentsOf: locals.read().rawBytes)
        }

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
                    Opcode.call(assertFuncIndex),
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

