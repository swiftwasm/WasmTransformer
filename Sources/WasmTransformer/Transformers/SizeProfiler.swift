public extension InputByteStream {
    mutating func readSectionsInfo() throws -> [SectionInfo] {
        precondition(offset == bytes.startIndex)
        readHeader()

        var result = [SectionInfo]()
        while !isEOF {
            let section = try readSectionInfo()
            result.append(section)
            skip(section.size)

        }
        return result
    }
}
