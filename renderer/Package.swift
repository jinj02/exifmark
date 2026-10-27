// swift-tools-version: 5.9
import PackageDescription
import Foundation

let jpegDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".build/jpeg")

let package = Package(
    name: "ExifmarkRenderer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "exifmark-render", targets: ["ExifmarkCLI"]),
        .executable(name: "exifmark-validate", targets: ["ExifmarkValidation"]),
    ],
    targets: [
        .target(name: "CExifmarkJPEG",
                cSettings: [.unsafeFlags(["-I", jpegDirectory.appendingPathComponent("include").path])],
                linkerSettings: [.unsafeFlags([jpegDirectory.appendingPathComponent("lib/libjpeg.a").path])]),
        .target(name: "ExifmarkCore", dependencies: ["CExifmarkJPEG"], resources: [.process("Resources")]),
        .executableTarget(name: "ExifmarkCLI", dependencies: ["ExifmarkCore"]),
        .executableTarget(name: "ExifmarkValidation", dependencies: ["ExifmarkCore"], path: "Tests/ExifmarkValidation"),
    ]
)
