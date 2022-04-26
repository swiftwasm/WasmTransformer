
public struct CustomSectionStripper: Transformer {

    public init() {}

    public static let metadata = TransformerMetadata(
        name: "strip-custom-section", description: "Strips custom sections from the wasm module"
    )

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
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
