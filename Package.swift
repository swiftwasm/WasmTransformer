// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "WasmTransformer",
    products: [
        .library(
            name: "WasmTransformer",
            targets: ["WasmTransformer"]
        ),
    ],
    targets: [
        .target(name: "WasmTransformer", dependencies: []),
        .testTarget(name: "WasmTransformerTests", dependencies: ["WasmTransformer"]),
    ]
)
