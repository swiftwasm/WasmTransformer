
public struct StackOverflowSanitizer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case unexpectedSection(UInt8)
    }

    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)

        while !input.isEOF {
            let sectionInfo = try input.readSectionInfo()

            switch sectionInfo.type {
            case .code:
                try transformCodeSection(input: &input, writer: &writer)
            default:
                try writer.writeBytes(input.bytes[sectionInfo.startOffset ..< sectionInfo.endOffset])
                input.skip(sectionInfo.size)
            }
        }
    }

    func transformCodeSection<Writer: OutputWriter>(input: inout InputByteStream, writer: inout Writer) throws {
        try writer.writeSection(.code) { writer in
            let count = Int(input.readVarUInt32())
            try writer.writeBytes(encodeULEB128(UInt32(count)))
            for _ in 0 ..< count {
                try transformFunction(input: &input, writer: writer, reportFuncIndex: 0)
            }
        }
    }

    
    func transformFunction(input: inout InputByteStream, writer: OutputWriter,
                           reportFuncIndex: UInt32) throws {
        let oldSize = Int(input.readVarUInt32())
        let bodyEnd = input.offset + oldSize
        var bodyBuffer: [UInt8] = []
        bodyBuffer.reserveCapacity(oldSize)

        let spLocalIdx: UInt32

        do {
            let count = input.readVarUInt32()
            bodyBuffer.append(contentsOf: encodeULEB128(count + 1))
            let existingLocalsStart = input.offset
            for _ in 0..<count {
                _ = input.readVarUInt32() // n
                _ = input.readUInt8() // value type
            }
            let existingLocalsEnd = input.offset
            bodyBuffer.append(contentsOf: input.bytes[existingLocalsStart..<existingLocalsEnd])
            // Add extra "local" to restore stack-pointer
            bodyBuffer.append(
                contentsOf: encodeULEB128(UInt32(1)) + [ValueType.i32.rawValue]
            )
            spLocalIdx = count
        }

        var nonGlobalSetInstStart = input.offset
        while input.offset < bodyEnd {
            let nonGlobalSetInstEnd = input.offset
            guard let globalIndex = try input.readGlobalSet(), globalIndex == 0 else {
                continue
            }
            bodyBuffer.append(contentsOf: input.bytes[nonGlobalSetInstStart..<nonGlobalSetInstEnd])
            nonGlobalSetInstStart = input.offset
            let opcodes = [
                Opcode.localSet(spLocalIdx),
                Opcode.localGet(spLocalIdx),
                Opcode.i32Const(0),
                Opcode.i32LtS,
                Opcode.if(.empty),
                // TODO: Opcode.call(reportFuncIndex),
                Opcode.unreachable,
                Opcode.end,
            ]
            bodyBuffer.append(contentsOf: opcodes.flatMap { $0.serialize() })
        }
        try writer.writeBytes(encodeULEB128(UInt32(bodyBuffer.count)))
        try writer.writeBytes(bodyBuffer)
    }



}

