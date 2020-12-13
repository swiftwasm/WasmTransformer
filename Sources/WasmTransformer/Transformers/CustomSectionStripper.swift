
public struct CustomSectionStripper {
    
    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: Writer) throws {
        input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)

        while !input.isEOF {
            let section = try input.readSectionInfo()
            input.skip(section.size)

            switch section.type {
            case .custom:
                break
            default:
                try writer.writeBytes(input.bytes[section.startOffset..<section.endOffset])
            }
            assert(input.offset == section.endOffset)
        }
    }
}
