// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    dependencies: [
        .package(url: "https://github.com/pvieito/PythonKit.git", .revision("8de2a3f1f8c1388e9fca84f192f96821d9ccd43d")),
        .package(name: "WasmTransformer", path: "../"),
    ],
    targets: [
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["WasmTransformer", "PythonKit"]),
    ]
)
