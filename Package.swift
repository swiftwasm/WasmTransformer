// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "WasmTransformer",
    products: [
        .library(
            name: "WasmTransformer",
            targets: ["WasmTransformer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .exact("1.0.0")),
    ],
    targets: [
        .executableTarget(name: "wasm-trans", dependencies: [
            "WasmTransformer",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .target(name: "WasmTransformer", dependencies: []),
        .testTarget(name: "WasmTransformerTests", dependencies: ["WasmTransformer"]),
    ]
)
