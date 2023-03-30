
public struct CustomSectionStripper: Transformer {

    private let stripIf: (_ name: String) -> Bool

    /// Create a new transformer of `CustomSectionStripper`
    /// - Parameter stripIf: The closure accepting the custom section name and
    /// returning `true` if it should strip the section.
    public init(
        stripIf: @escaping (_ name: String) -> Bool = { _ in true }
    ) {
        self.stripIf = stripIf
    }

    public let metadata = TransformerMetadata(
        name: "strip-custom-section", description: "Strips custom sections from the wasm module"
    )

    public func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws {
        let version = try input.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)

        while !input.isEOF {
            let section = try input.readSectionInfo()

            let shouldStrip: Bool
            if section.type == .custom {
                let name = input.readString()
                shouldStrip = stripIf(name)
            } else {
                shouldStrip = false
            }
            input.seek(section.endOffset)
            if !shouldStrip {
                try writer.writeBytes(input.bytes[section.startOffset..<section.endOffset])
            }
            assert(input.offset == section.endOffset)
        }
    }
}
