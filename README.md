# WasmTransformer

![Test](https://github.com/swiftwasm/swift-wasm-transformer/workflows/Test/badge.svg)

A package which provides transformation operation for WebAssembly binary. Inspired by [Rust implementation](https://github.com/wasmerio/wasmer-js/tree/master/crates/wasm_transformer)

## Available transformations

### `lowerI64Imports`


```swift
public func lowerI64Imports(_ input: [UInt8]) throws -> [UInt8]
```

Inserts trampoline functions for imports that have i64 params or returns. This is useful for running Wasm modules in browsers that do not support JavaScript BigInt -> Wasm i64 integration. Especially in the case for i64 WASI Imports.


### `stripCustomSections`

```swift
public func stripCustomSections(_ input: [UInt8]) throws -> [UInt8]
```

Strip all custom sections from input WebAssembly binary.


## Testing

1. Set environment variable `SWIFT_TOOLCHAIN` to the path to your SwiftWasm toolchain.
   e.g. `$HOME/Library/Developer/Toolchains/swift-wasm-5.7.3-RELEASE.xctoolchain/usr`
2. Set up testing fixtures by: `(cd ./Fixtures/ && npm install && npm run build && make all)`
3. Run `swift test`

