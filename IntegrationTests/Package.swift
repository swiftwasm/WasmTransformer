// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    dependencies: [
        .package(url: "https://github.com/pvieito/PythonKit.git", .revision("b6513c3")),
        .package(name: "WasmTransformer", path: "../"),
    ],
    targets: [
        .target(
            name: "IntegrationTests",
            dependencies: ["WasmTransformer", "PythonKit"]),
    ]
)
