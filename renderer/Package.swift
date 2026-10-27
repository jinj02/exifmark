// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExifyRenderer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "exify-render", targets: ["ExifyCLI"]),
        .executable(name: "exify-validate", targets: ["ExifyValidation"]),
    ],
    targets: [
        .target(name: "ExifyCore", resources: [.process("Resources")]),
        .executableTarget(name: "ExifyCLI", dependencies: ["ExifyCore"]),
        .executableTarget(name: "ExifyValidation", dependencies: ["ExifyCore"], path: "Tests/ExifyValidation"),
    ]
)
