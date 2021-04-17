protocol ByteEncodable {
    func encode<Writer: OutputWriter>(to writer: inout Writer) throws
}

extension OutputWriter {
    
    mutating func writeSection<T>(_ type: SectionType, bodyWriter: (inout InMemoryOutputWriter) throws -> T) throws -> T {
        try writeByte(type.rawValue)
        var buffer = InMemoryOutputWriter()
        let result = try bodyWriter(&buffer)
        try writeBytes(encodeULEB128(UInt32(buffer.bytes().count)))
        try writeBytes(buffer.bytes())
        return result
    }

    mutating func writeVectorSection<Reader: VectorSectionReader>(
        type: SectionType,
        reader: Reader, extras: [Reader.Item] = []
    ) throws where Reader.Item: ByteEncodable {
        let count = reader.count + UInt32(extras.count)
        try self.writeSection(type) { buffer in
            try buffer.writeBytes(encodeULEB128(count))
            for result in reader {
                let entry = try result.get()
                try entry.encode(to: &buffer)
            }
            for extra in extras {
                try extra.encode(to: &buffer)
            }
        }
    }

    mutating func writeVectorSection(
        type: SectionType,
        count: UInt32,
        writeItems: (inout InMemoryOutputWriter) throws -> Void
    ) throws {
        try self.writeSection(type) { buffer in
            try buffer.writeBytes(encodeULEB128(count))
            try writeItems(&buffer)
        }
    }

    mutating func writeVectorSection<Item: ByteEncodable>(
        type: SectionType,
        items: [Item] = []
    ) throws {
        let count = UInt32(items.count)
        try self.writeSection(type) { buffer in
            try buffer.writeBytes(encodeULEB128(count))
            for extra in items {
                try extra.encode(to: &buffer)
            }
        }
    }
}

extension FuncSignature: ByteEncodable {
    func encode<Writer: OutputWriter>(to writer: inout Writer) throws {
        try writer.writeByte(0x60)
        try writer.writeResultTypes(params)
        try writer.writeResultTypes(results)
    }
}

extension Import: ByteEncodable {
    func encode<Writer: OutputWriter>(to writer: inout Writer) throws {
        try writer.writeString(module)
        try writer.writeString(field)
        switch descriptor {
        case .function(let sigIndex):
            try writer.writeByte(ExternalKind.func.rawValue)
            try writer.writeBytes(encodeULEB128(sigIndex))
        case .table(let rawBytes):
            try writer.writeByte(ExternalKind.table.rawValue)
            try writer.writeBytes(rawBytes)
        case .memory(let rawBytes):
            try writer.writeByte(ExternalKind.memory.rawValue)
            try writer.writeBytes(rawBytes)
        case .global(let rawBytes):
            try writer.writeByte(ExternalKind.global.rawValue)
            try writer.writeBytes(rawBytes)
        }
    }
}

extension SignatureIndex: ByteEncodable {
    func encode<Writer: OutputWriter>(to writer: inout Writer) throws {
        try writer.writeBytes(encodeULEB128(value))
    }
}
