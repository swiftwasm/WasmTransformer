public struct TransformerMetadata {
    public var name: String
    public var description: String
}

public protocol Transformer {
    var metadata: TransformerMetadata { get }
    func transform<Writer: OutputWriter>(_ input: inout InputByteStream, writer: inout Writer) throws
}

public func lowerI64Imports(
    _ input: [UInt8],
    shouldLower: @escaping (Import) -> Bool = { _ in true }
) throws -> [UInt8] {
    let transformer = I64ImportTransformer(shouldLower: shouldLower)
    var inputStream = InputByteStream(bytes: input)
    var writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: &writer)
    return writer.bytes()
}

public func stripCustomSections(_ input: [UInt8]) throws -> [UInt8] {
    let transformer = CustomSectionStripper()
    var inputStream = InputByteStream(bytes: input)
    var writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: &writer)
    return writer.bytes()
}
