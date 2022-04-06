import Foundation

guard CommandLine.arguments.count == 2 else {
    print("Usage: \(CommandLine.arguments[0]) <support.o>")
    exit(1)
}

let objectFile = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))

let sourceCode = """
// GENERATED FROM Tools/GenerateStackOverflowSanitizerSupport.swift

extension StackOverflowSanitizer {
    public static let supportObjectFile: [UInt8] = [
        \(objectFile.map { String(format: "0x%02x", $0) }.joined(separator: ", "))
    ]
}
"""

print(sourceCode)
