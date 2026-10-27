// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExifmarkRenderer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "exifmark-render", targets: ["ExifmarkCLI"]),
        .executable(name: "exifmark-validate", targets: ["ExifmarkValidation"]),
    ],
    targets: [
        .target(name: "ExifmarkCore", resources: [.process("Resources")]),
        .executableTarget(name: "ExifmarkCLI", dependencies: ["ExifmarkCore"]),
        .executableTarget(name: "ExifmarkValidation", dependencies: ["ExifmarkCore"], path: "Tests/ExifmarkValidation"),
    ]
)
