public enum ModuleSection {
    case type(TypeSectionReader)
    case `import`(ImportSectionReader)
    case function(FunctionSectionReader)
    case element(ElementSectionReader)
    case code(CodeSectionReader)
    case rawSection(type: SectionType, content: ArraySlice<UInt8>)
}

public struct ModuleReader {
    enum Error: Swift.Error {
        case invalidMagic
    }
    var input: InputByteStream
    
    public init(input: InputByteStream) {
        self.input = input
    }
    
    public var isEOF: Bool { input.isEOF }

    mutating func readHeader() throws -> ArraySlice<UInt8> {
        return try input.readHeader()
    }

    public mutating func readSection() throws -> ModuleSection {
        let sectionInfo = try input.readSectionInfo()
        defer {
            input.seek(sectionInfo.endOffset)
        }
        switch sectionInfo.type {
        case .type:
            return .type(TypeSectionReader(input: input))
        case .import:
            return .import(ImportSectionReader(input: input))
        case .function:
            return .function(FunctionSectionReader(input: input))
        case .element:
            return .element(ElementSectionReader(input: input))
        case .code:
            return .code(CodeSectionReader(input: input))
        default:
            return .rawSection(
                type: sectionInfo.type,
                content: input.bytes[sectionInfo.contentRange]
            )
        }
    }
}
