public struct SectionInfo: Equatable {
    public let startOffset: Int
    public let contentStart: Int
    public var endOffset: Int {
        contentStart + size
    }
    public var contentRange: Range<Int> {
        contentStart..<endOffset
    }
    public let type: SectionType
    public let size: Int
}

