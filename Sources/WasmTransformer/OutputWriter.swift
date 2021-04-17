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
