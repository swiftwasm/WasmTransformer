public struct I64ImportTransformer: Transformer {
    enum Error: Swift.Error {
        case invalidExternalKind(UInt8)
        case expectFunctionSection
        case unexpectedSection(UInt8)
    }

    typealias ImportFuncReplacement = (index: Int, toTypeIndex: Int)
    
    public init() {}

    public let metadata = TransformerMetadata(
        name: "i64-to-i32-lowering",
        description: "Replaces all i64 imports with i32 imports"
    )

    public func transform<Writer: OutputWriter>(
        _ input: inout InputByteStream,
        writer: inout Writer
    ) throws {
        var moduleReader = ModuleReader(input: input)
        let version = try moduleReader.readHeader()
        try writer.writeBytes(magic)
        try writer.writeBytes(version)

        var importedFunctionCount = 0
        var trampolines = Trampolines()
        do {
            // Phase 1. Scan Type and Import sections to determine import records
            //          which will be lowered.
            var copyingSections: [(type: SectionType, content: ArraySlice<UInt8>)] = []
            var typeSection: [FuncSignature] = []
            var replacements: [ImportFuncReplacement] = []
            var importSection: ImportSectionReader?
            Phase1: while !moduleReader.isEOF {
                switch try moduleReader.readSection() {
                case .type(let reader):
                    typeSection = try reader.collect()
                case .import(var reader):
                    importSection = reader
                    importedFunctionCount = try scan(
                        importSection: &reader,
                        typeSection: &typeSection, replacements: &replacements,
                        trampolines: &trampolines
                    )
                    break Phase1
                case .rawSection(type: .custom, content: let content):
                    copyingSections.append((type: .custom, content: content))
                case .element:
                    throw Error.unexpectedSection(SectionType.elem.rawValue)
                case .function(_):
                    throw Error.unexpectedSection(SectionType.function.rawValue)
                case .code(_):
                    throw Error.unexpectedSection(SectionType.code.rawValue)
                case .rawSection(let type, _):
                    throw Error.unexpectedSection(type.rawValue)
                }
            }

            // Phase 2. Write out Type and Import section based on scanned results.
            try writer.writeVectorSection(type: .type, items: typeSection)
            if var importSection = importSection {
                try writer.writeVectorSection(type: .import, count: importSection.count) { writer in
                    for index in 0 ..< importSection.count {
                        var entry = try importSection.read()
                        switch entry.descriptor {
                        case .function:
                            if let replacement = replacements.first(where: { $0.index == index }) {
                                entry.descriptor = .function(UInt32(replacement.toTypeIndex))
                            }
                        default: break
                        }
                        try entry.encode(to: &writer)
                    }
                }
            }

            for section in copyingSections {
                try writer.writeSection(section.type) { buffer in
                    try buffer.writeBytes(section.content)
                }
            }
        }

        // After here, we can emit binary sequentially

        var originalFuncCount: Int?
        while !moduleReader.isEOF {
            switch try moduleReader.readSection() {
            case .type, .import:
                fatalError("unreachable")
            case .function(let reader):
                // Phase 3. Write out Func section and add trampoline signatures.
                try writer.writeVectorSection(type: .function, reader: reader, extras: trampolines.map {
                    SignatureIndex(value: UInt32($0.fromSignatureIndex))
                })
                originalFuncCount = Int(reader.count) + importedFunctionCount
            case .element(var reader):
                // Phase 4. Read Elem section and rewrite i64 functions with trampoline functions.
                guard let originalFuncCount = originalFuncCount else {
                    throw Error.expectFunctionSection
                }
                try transformElemSection(
                    input: &reader, writer: &writer,
                    trampolines: trampolines, originalFuncCount: originalFuncCount
                )
            case .code(var reader):
                // Phase 5. Read Code section and rewrite i64 function calls with trampoline function call.
                //          And add trampoline functions at the tail
                guard let originalFuncCount = originalFuncCount else {
                    throw Error.expectFunctionSection
                }
                try transformCodeSection(
                    input: &reader, writer: &writer,
                    trampolines: trampolines, originalFuncCount: originalFuncCount
                )
            case .rawSection(let type, let content):
                try writer.writeSection(type) { buffer in
                    try buffer.writeBytes(content)
                }
            }
        }
    }

    /// https://webassembly.github.io/spec/core/binary/modules.html#import-section
    /// Returns a count of imported functions
    func scan(importSection: inout ImportSectionReader,
              typeSection: inout [FuncSignature],
              replacements: inout [ImportFuncReplacement],
              trampolines: inout Trampolines) throws -> Int
    {
        var importFuncCount = 0
        for (index, result) in importSection.enumerated() {
            let entry = try result.get()
            switch entry.descriptor {
            case .function(let sigIndex):
                let signatureIndex = Int(sigIndex)
                let signature = typeSection[signatureIndex]
                defer { importFuncCount += 1 }
                guard signature.hasI64Param() else { continue }
                let toTypeIndex = typeSection.count
                let toSignature = signature.lowered()
                typeSection.append(toSignature)
                replacements.append(
                    (index: Int(index), toTypeIndex: toTypeIndex)
                )
                trampolines.add(
                    importIndex: importFuncCount, from: signature,
                    fromIndex: signatureIndex, to: toSignature
                )
            case .table, .memory, .global: break
            }
        }
        return importFuncCount
    }
}

private func transformCodeSection<Writer: OutputWriter>(
    input: inout CodeSectionReader, writer: inout Writer,
    trampolines: Trampolines, originalFuncCount: Int) throws
{
    let count = input.count
    let newCount = count + UInt32(trampolines.count)
    try writer.writeVectorSection(type: .code, count: newCount) { writer in
        for _ in 0 ..< input.count {
            let body = try input.read()
            let bodyBuffer = try replaceFunctionCall(body: body) { funcIndex in
                guard let (_, trampolineIndex) = trampolines.trampoline(byBaseFuncIndex: Int(funcIndex)) else { return nil }
                return UInt32(originalFuncCount + trampolineIndex)
            }
            let newSize = bodyBuffer.count
            try writer.writeBytes(encodeULEB128(UInt32(newSize)))
            try writer.writeBytes(bodyBuffer)
        }
        for trampoline in trampolines {
            try trampoline.write(to: writer)
        }
    }
}
private func replaceFunctionCall(
    body: FunctionBody,
    replace: (_ funcIndex: UInt32) -> UInt32?
) throws -> [UInt8] {
    var locals = body.locals()
    var bodyBuffer: [UInt8] = []
    bodyBuffer.reserveCapacity(Int(body.size))

    bodyBuffer.append(contentsOf: encodeULEB128(locals.count))
    for _ in 0 ..< locals.count {
        try bodyBuffer.append(contentsOf: locals.read().rawBytes)
    }

    var operators = locals.operators()
    var nonCallInstStart = operators.offset
    while operators.offset < body.endOffset {
        let nonCallInstEnd = operators.offset
        guard let funcIndex = try operators.readCallInst(),
              let newFuncIndex = replace(funcIndex) else {
            continue
        }
        bodyBuffer.append(contentsOf: operators.bytes[nonCallInstStart..<nonCallInstEnd])
        nonCallInstStart = operators.offset

        let callInst = Opcode.call(newFuncIndex)
        bodyBuffer.append(contentsOf: callInst.serialize())
    }
    bodyBuffer.append(contentsOf: operators.bytes[nonCallInstStart..<operators.offset])
    return bodyBuffer
}

/// Read Elem section and rewrite i64 functions with trampoline functions.
private func transformElemSection<Writer: OutputWriter>(
    input: inout ElementSectionReader, writer: inout Writer,
    trampolines: Trampolines, originalFuncCount: Int
) throws {
    try writer.writeVectorSection(type: .elem, count: input.count) { writer in
        for result in input {
            var entry = try result.get()
            try writer.writeBytes(encodeULEB128(entry.flags))
            try writer.writeBytes(entry.initExpr)
            try writer.writeBytes(encodeULEB128(entry.items.count))
            for _ in 0..<entry.items.count {
                let funcIndex = entry.items.read()
                if let (_, index) = trampolines.trampoline(byBaseFuncIndex: Int(funcIndex.value)) {
                    try writer.writeBytes(encodeULEB128(UInt32(index + originalFuncCount)))
                } else {
                    try writer.writeBytes(encodeULEB128(funcIndex.value))
                }
            }
        }
    }
}

fileprivate extension FuncSignature {
    func lowered() -> FuncSignature {
        func transform(_ type: ValueType) -> ValueType {
            if case .i64 = type { return .i32 }
            else { return type }
        }
        return FuncSignature(
            params: params.map(transform),
            results: results
        )
    }

    func hasI64Param() -> Bool {
        for param in params {
            if param == ValueType.i64 {
                return true
            }
        }
        return false
    }
}
