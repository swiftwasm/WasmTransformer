import WasmTransformer
import ArgumentParser
import Foundation

struct TransformerOption: EnumerableFlag, CustomStringConvertible {
    let transformer: Transformer

    var description: String {
        transformer.metadata.name
    }

    static func name(for value: TransformerOption) -> NameSpecification {
        .long
    }

    static func help(for value: TransformerOption) -> ArgumentHelp? {
        ArgumentHelp(value.transformer.metadata.description)
    }

    static var allCases: [TransformerOption] {
        [
            I64ImportTransformer(),
            CustomSectionStripper(),
            StackOverflowSanitizer()
        ]
            .map(TransformerOption.init(transformer: ))
    }

    static func == (lhs: TransformerOption, rhs: TransformerOption) -> Bool {
        return lhs.description == rhs.description
    }
}

struct WasmTrans: ParsableCommand {

    @Argument
    var input: String
    @Option(name: .shortAndLong, help: "Output file")
    var output: String

    @Flag
    var passes: [TransformerOption] = []

    mutating func run() throws {
        var nextBytes = try Array(Data(contentsOf: URL(fileURLWithPath: input)))
        for pass in passes {
            var inputStream = InputByteStream(bytes: nextBytes)
            var writer = InMemoryOutputWriter(reservingCapacity: nextBytes.count)
            try pass.transformer.transform(&inputStream, writer: &writer)
            nextBytes = writer.bytes()
        }
        try Data(nextBytes).write(to: URL(fileURLWithPath: output))
    }
} 

WasmTrans.main()
