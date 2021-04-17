public protocol OutputWriter {
    func writeByte(_ byte: UInt8) throws
    func writeBytes<S: Sequence>(_ bytes: S) throws where S.Element == UInt8
}

extension OutputWriter {
    func writeString(_ value: String) throws {
        let bytes = value.utf8
        try writeBytes(encodeULEB128(UInt32(bytes.count)))
        try writeBytes(bytes)
    }

    /// https://webassembly.github.io/spec/core/binary/types.html#result-types
    func writeResultTypes(_ types: [ValueType]) throws {
        try writeBytes(encodeULEB128(UInt32(types.count)))
        for type in types {
            try writeByte(type.rawValue)
        }
    }

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

public class InMemoryOutputWriter: OutputWriter {
    private var _bytes: [UInt8] = []
    
    public init(reservingCapacity capacity: Int = 0) {
        _bytes.reserveCapacity(capacity)
    }

    public func writeByte(_ byte: UInt8) throws {
        _bytes.append(byte)
    }
    
    public func writeBytes<S>(_ newBytes: S) throws where S : Sequence, S.Element == UInt8 {
        _bytes.append(contentsOf: newBytes)
    }

    public func bytes() -> [UInt8] { _bytes }
}
