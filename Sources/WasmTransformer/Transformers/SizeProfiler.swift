public func sizeProfiler(_ bytes: [UInt8]) throws -> [SectionInfo] {
    var input = InputByteStream(bytes: bytes)
    input.readHeader()

    var result = [SectionInfo]()
    while !input.isEOF {
        let section = try input.readSectionInfo()
        result.append(section)
        input.skip(section.size)

    }
    return result
}
