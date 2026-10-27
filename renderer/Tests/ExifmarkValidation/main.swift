import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ExifmarkCore
import Darwin


private var failures = 0
private func fail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}
private func check(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
private func reject(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    check(!value, file: file, line: line)
}
private func equal<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    if lhs != rhs { fail("\(lhs) != \(rhs)", file: file, line: line) }
}
private func notNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    check(value != nil, file: file, line: line)
}
private func isNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    check(value == nil, file: file, line: line)
}
private func greater<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    check(lhs > rhs, file: file, line: line)
}
private struct MissingValue: Error {}
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw MissingValue() }; return value
}
private func throwsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression(); fail("Expected error", file: file, line: line) } catch {}
}

final class CardRendererTests {
    var directory: URL!

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("exifmark-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func fixture(width: Int = 320, height: Int = 240, orientation: Int = 1,
                 profile: CFString = CGColorSpace.sRGB, gps: Bool = false) throws -> URL {
        let space = CGColorSpace(name: profile)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height / 2))
        context.setFillColor(red: 0.1, green: 0.2, blue: 0.85, alpha: 1)
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        context.setFillColor(red: 0.9, green: 0.75, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: height / 2, width: width - width / 2, height: height - height / 2))
        let image = context.makeImage()!
        let path = directory.appendingPathComponent("input-\(UUID().uuidString).tif")
        let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        var properties: [String: Any] = [
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "SONY",
                kCGImagePropertyTIFFModel as String: "ILCE-7M4",
                kCGImagePropertyTIFFCopyright as String: "exifmark test copyright",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:10:27 09:41:30",
                kCGImagePropertyExifPixelXDimension as String: width,
                kCGImagePropertyExifPixelYDimension as String: height,
            ],
            kCGImagePropertyIPTCDictionary as String: [kCGImagePropertyIPTCCaptionAbstract as String: "中文说明"],
        ]
        if gps {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: 31.2,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 121.4,
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        check(CGImageDestinationFinalize(destination))
        return path
    }

    func properties(_ url: URL) throws -> [String: Any] {
        let source = try unwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try unwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    func testDimensionsAcrossAspectRatiosAndThemes() throws {
        for (width, height) in [(1200, 800), (800, 1200), (1600, 400), (320, 240), (667, 1000), (17, 11)] {
            let input = try fixture(width: width, height: height)
            for theme in [Theme.white, .black] {
                for layout in [Layout.bordered, .bottomOnly] {
                    let output = directory.appendingPathComponent("\(width)-\(theme.rawValue)-\(layout.rawValue).jpg")
                    let result = try CardRenderer().render(RenderRequest(input: input.path, output: output.path,
                        theme: theme, layout: layout,
                        camera: "ILCE-7M4", lens: String(repeating: "超长镜头 FE 24-70mm F2.8 GM II · ", count: 12),
                        exposure: "f/2.8 · 1/8000s · ISO 102400", capturedAt: "2026.10.27 09:41"))
                    let actual = try properties(output)
                    let border = layout == .bordered ? Int((Double(width) * 0.02).rounded()) : 0
                    let footer = Int((Double(width) * 0.08).rounded())
                    equal(result.width, width + border * 2)
                    equal(result.height, height + border + footer)
                    equal(result.footerHeight, footer)
                    equal(actual[kCGImagePropertyPixelWidth as String] as? Int, result.width)
                    equal(actual[kCGImagePropertyPixelHeight as String] as? Int, result.height)
                }
            }
        }
    }

    func testAllEightOrientationsAreNormalized() throws {
        for orientation in 1...8 {
            let input = try fixture(orientation: orientation)
            for layout in [Layout.bordered, .bottomOnly] {
                let output = directory.appendingPathComponent("orientation-\(orientation)-\(layout.rawValue).jpg")
                let result = try CardRenderer().render(RenderRequest(input: input.path, output: output.path, layout: layout))
                let bordered = layout == .bordered
                equal(result.width, orientation >= 5 ? (bordered ? 250 : 240) : (bordered ? 332 : 320))
                equal(result.height, orientation >= 5 ? (bordered ? 344 : 339) : (bordered ? 272 : 266))
                let actual = try properties(output)
                equal(actual[kCGImagePropertyOrientation as String] as? Int ?? 1, 1)
                let exif = actual[kCGImagePropertyExifDictionary as String] as? [String: Any]
                equal(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int, result.width)
                equal(exif?[kCGImagePropertyExifPixelYDimension as String] as? Int, result.height)
            }
        }
    }

    func testAllowedMetadataAndAdobeRGBProfileSurvive() throws {
        let input = try fixture(profile: CGColorSpace.adobeRGB1998, gps: true)
        let output = directory.appendingPathComponent("metadata.jpg")
        try CardRenderer().render(RenderRequest(input: input.path, output: output.path))
        let actual = try properties(output)
        let exif = try unwrap(actual[kCGImagePropertyExifDictionary as String] as? [String: Any])
        equal(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:10:27 09:41:30")
        let tiff = try unwrap(actual[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        equal(tiff[kCGImagePropertyTIFFModel as String] as? String, "ILCE-7M4")
        equal(tiff[kCGImagePropertyTIFFCopyright as String] as? String, "exifmark test copyright")
        let iptc = try unwrap(actual[kCGImagePropertyIPTCDictionary as String] as? [String: Any])
        equal(iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String, "中文说明")
        notNil(actual[kCGImagePropertyGPSDictionary as String])
        let source = try unwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        equal(image.colorSpace?.name.map { $0 as String }, CGColorSpace.adobeRGB1998 as String)
    }

    func testStrippedGPSIsNotReintroducedByVisibleFields() throws {
        let input = try fixture()
        let output = directory.appendingPathComponent("privacy.jpg")
        try CardRenderer().render(RenderRequest(input: input.path, output: output.path,
            camera: "SONY", capturedAt: "2026.10.27 09:41"))
        isNil(try properties(output)[kCGImagePropertyGPSDictionary as String])
    }

    func testTIFFStagingPreservesMetadataAndProfile() throws {
        let input = try fixture(profile: CGColorSpace.adobeRGB1998, gps: true)
        let output = directory.appendingPathComponent("lossless-card.tiff")
        let result = try CardRenderer().render(RenderRequest(input: input.path, output: output.path))
        let actual = try properties(output)
        equal(actual[kCGImagePropertyPixelWidth as String] as? Int, result.width)
        equal(actual[kCGImagePropertyPixelHeight as String] as? Int, result.height)
        let tiff = try unwrap(actual[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        equal(tiff[kCGImagePropertyTIFFModel as String] as? String, "ILCE-7M4")
        equal(tiff[kCGImagePropertyTIFFCopyright as String] as? String, "exifmark test copyright")
        notNil(actual[kCGImagePropertyGPSDictionary as String])
        let source = try unwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        equal(CGImageSourceGetType(source).map { $0 as String }, UTType.tiff.identifier)
        let image = try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        equal(image.colorSpace?.name.map { $0 as String }, CGColorSpace.adobeRGB1998 as String)
    }

    func testJPEGInstallationPreservesExactBytesAndExistingOutputOnFailure() throws {
        let input = try fixture()
        let jpeg = directory.appendingPathComponent("Lightroom final.jpg")
        try CardRenderer().render(RenderRequest(input: input.path, output: jpeg.path))
        let bytes = try Data(contentsOf: jpeg)
        let output = directory.appendingPathComponent("成片 ' $() ` &.jpg")
        try Data("previous output".utf8).write(to: output)
        try JPEGInstallRequest(input: jpeg.path, output: output.path).install()
        equal(try Data(contentsOf: output), bytes)
        equal(try Data(contentsOf: jpeg), bytes)
        throwsError(try JPEGInstallRequest(input: input.path, output: output.path).install())
        throwsError(try JPEGInstallRequest(input: jpeg.path, output: jpeg.path).install())
        throwsError(try JPEGInstallRequest(input: "/missing/file.jpg", output: output.path).install())
        equal(try Data(contentsOf: output), bytes)
        reject(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".exifmark-") })
    }

    func testAtomicOverwriteAndSourceUnchangedWithSpecialPaths() throws {
        let fixture = try fixture()
        let input = directory.appendingPathComponent("原片 ' $() ` &.tif")
        try FileManager.default.moveItem(at: fixture, to: input)
        let before = try Data(contentsOf: input)
        let output = directory.appendingPathComponent("成片 ' $() ` &.jpg")
        try Data("previous output".utf8).write(to: output)
        try CardRenderer().render(RenderRequest(input: input.path, output: output.path))
        equal(try Data(contentsOf: input), before)
        greater(try Data(contentsOf: output).count, 1000)
        reject(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".exifmark-") })
    }

    func testInvalidRequestsDoNotOverwriteExistingOutput() throws {
        let input = try fixture()
        let output = directory.appendingPathComponent("protected.jpg")
        let original = Data("previous output".utf8)
        try original.write(to: output)
        throwsError(try CardRenderer().render(RenderRequest(input: input.path, output: output.path, quality: 2)))
        equal(try Data(contentsOf: output), original)
        throwsError(try CardRenderer().render(RenderRequest(input: input.path, output: input.path)))
        throwsError(try CardRenderer().render(RenderRequest(input: "/missing/image.tif", output: output.path)))
        equal(try Data(contentsOf: output), original)
        throwsError(try CardRenderer().render(RenderRequest(input: input.path, output: directory.appendingPathComponent("missing/photo.jpg").path)))
        reject(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".exifmark-") })
    }
}

let suite = CardRendererTests()
let cases: [(String, () throws -> Void)] = [
    ("dimensions and themes", suite.testDimensionsAcrossAspectRatiosAndThemes),
    ("eight orientations", suite.testAllEightOrientationsAreNormalized),
    ("metadata and AdobeRGB", suite.testAllowedMetadataAndAdobeRGBProfileSurvive),
    ("stripped GPS", suite.testStrippedGPSIsNotReintroducedByVisibleFields),
    ("lossless TIFF metadata and profile", suite.testTIFFStagingPreservesMetadataAndProfile),
    ("JPEG bytes and failure protection", suite.testJPEGInstallationPreservesExactBytesAndExistingOutputOnFailure),
    ("atomic writes and special paths", suite.testAtomicOverwriteAndSourceUnchangedWithSpecialPaths),
    ("errors preserve output", suite.testInvalidRequestsDoNotOverwriteExistingOutput),
]
for (name, test) in cases {
    let before = failures
    do {
        try suite.setUpWithError()
        defer { try? suite.tearDownWithError() }
        try autoreleasepool { try test() }
    } catch { fail("\(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("Native validation: \(cases.count) scenarios, \(failures) failures")
exit(failures == 0 ? 0 : 1)
