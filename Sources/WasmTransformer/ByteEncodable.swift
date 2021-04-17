protocol ByteEncodable {
    func encode<Writer: OutputWriter>(to writer: inout Writer) throws
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
