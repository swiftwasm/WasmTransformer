public protocol VectorSectionReader: Sequence where Element == Result<Item, Error> {
    associatedtype Item
    var count: UInt32 { get }
    mutating func read() throws -> Item
}

public struct VectorSectionIterator<Reader: VectorSectionReader>: IteratorProtocol {
    private(set) var reader: Reader
    private(set) var left: UInt32
    init(reader: Reader, count: UInt32) {
        self.reader = reader
        self.left = count
    }
    private var end: Bool = false
    public mutating func next() -> Reader.Element? {
        guard !end else { return nil }
        guard left != 0 else { return nil }
        let result = Result(catching: { try reader.read() })
        left -= 1
        switch result {
        case .success: return result
        case .failure:
            end = true
            return result
        }
    }
}

extension VectorSectionReader {
    __consuming public func makeIterator() -> VectorSectionIterator<Self> {
        VectorSectionIterator(reader: self, count: count)
    }

    public func collect() throws -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(Int(count))
        for result in self {
            try items.append(result.get())
        }
        return items
    }
}
