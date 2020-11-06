
public struct CustomSectionStripper {
    
    public init() {}

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: Writer) throws {
        let maybeMagic = input.read(4)
        assert(maybeMagic.elementsEqual(magic))
        try writer.writeBytes(magic)
        let maybeVersion = input.read(4)
        assert(maybeVersion.elementsEqual(version))
        try writer.writeBytes(version)

        while !input.isEOF {
            let offset = input.offset
            let type = input.readUInt8()
            let size = Int(input.readVarUInt32())
            let contentStart = input.offset
            let sectionType = SectionType(rawValue: type)

            input.read(size)
            switch sectionType {
            case .custom:
                break
            default:
                try writer.writeBytes(input.bytes[offset..<contentStart + size])
            }
            assert(input.offset == contentStart + size)
        }
    }
}
