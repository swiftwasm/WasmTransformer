public func lowerI64Imports(_ input: [UInt8]) throws -> [UInt8] {
    let transformer = I64ImportTransformer()
    var inputStream = InputByteStream(bytes: input)
    var writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: &writer)
    return writer.bytes()
}

public func stripCustomSections(_ input: [UInt8]) throws -> [UInt8] {
    let transformer = CustomSectionStripper()
    var inputStream = InputByteStream(bytes: input)
    let writer = InMemoryOutputWriter()
    try transformer.transform(&inputStream, writer: writer)
    return writer.bytes()
}
