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

    func testCameraBrandResolution() throws {
        for brand in CameraBrand.allCases {
            equal(CameraBrand.resolve(make: brand.rawValue.uppercased(), model: ""), brand)
            equal(CameraBrand.resolve(make: "", model: brand.rawValue + " Model"), brand)
        }
        equal(CameraBrand.resolve(make: "NIKON CORPORATION", model: "Z 8"), .nikon)
        equal(CameraBrand.resolve(make: "RICOH IMAGING COMPANY, LTD.", model: "PENTAX K-1"), .pentax)
        equal(CameraBrand.resolve(make: "Phase One A/S", model: "IQ4"), .phaseone)
        equal(CameraBrand.resolve(make: "", model: "ILCE-7M4"), .sony)
        isNil(CameraBrand.resolve(make: "Unknown", model: "ILCE-7M4"))
        isNil(CameraBrand.resolve(make: "", model: "Acme Canon-compatible camera"))
        isNil(CameraBrand.resolve(make: "", model: ""))
        let legacy = """
        {"version":1,"input":"/source.tif","output":"/output.jpg","theme":"white",        "camera":"ILCE-7M4","lens":"","exposure":"","capturedAt":"","quality":0.9}
        """
        equal(try JSONDecoder().decode(RenderRequest.self, from: Data(legacy.utf8)).cameraMake, "")
        let decoded = try JSONDecoder().decode(RenderRequest.self, from: Data(legacy.utf8))
        equal(decoded.watermarkStyle, .detailed)
        equal(decoded.focalLength, "")
        var modern = decoded
        modern.theme = .blurred
        modern.watermarkStyle = .centered
        modern.focalLength = "54mm"
        let roundTrip = try JSONDecoder().decode(RenderRequest.self, from: JSONEncoder().encode(modern))
        equal(roundTrip.theme, .blurred)
        equal(roundTrip.watermarkStyle, .centered)
        equal(roundTrip.focalLength, "54mm")
    }

    func testCameraNames() throws {
        let names = CameraNames.bundled
        for (make, model, expected) in [
            ("SONY", "ILCE-7M3", "α7 III"), ("SONY", "ILCE-7M4", "α7 IV"),
            ("SONY", "ILCE-7RM4", "α7R IV"), ("SONY", "ILCE-7RM5", "α7R V"),
            ("Canon", "Canon EOS R5", "EOS R5"), ("Canon", "Canon EOS R5 Mark II", "EOS R5 Mark II"),
            ("NIKON CORPORATION", "NIKON Z 8", "Z 8"), ("FUJIFILM", "X-T5", "X-T5"),
            ("RICOH IMAGING COMPANY, LTD.", "PENTAX K-1", "K-1"),
            ("RICOH IMAGING COMPANY, LTD.", "PENTAX K-1 Mark II", "K-1 Mark II"),
            ("RICOH IMAGING COMPANY, LTD.", "GR III", "GR III"), ("RICOH", "GR IIIx", "GR IIIx"),
            ("Panasonic", "DC-S5M2", "LUMIX S5II"), ("Panasonic", "DC-S5M2X", "LUMIX S5IIX"),
            ("  sony\n", " ilce-7m4 ", "α7 IV"), ("NIKON", "Z  8", "Z 8"),
        ] {
            equal(names.displayName(make: make, model: model), expected)
        }
        for (make, model) in [
            ("Canon", "Canon EOS R5 C"), ("RICOH", "GR IIIx HDF"), ("Unknown", "ILCE-7M4"),
            ("Acme SONY compatible", "ILCE-7M4"), ("", "ILCE-7M4"), ("SONY", ""),
            ("SONY", "  Unknown camera X-II "), ("", ""),
        ] {
            equal(names.displayName(make: make, model: model), model)
        }
        let raw = "  ILCE-7M4\n"
        equal(names.displayName(make: "SONY", model: raw, style: .exif), raw)
        equal(names.displayName(make: "SONY", model: raw, customName: " 我的相机α7 IV "), "我的相机α7 IV")
        equal(names.displayName(make: "SONY", model: raw, style: .exif, customName: "自定义"), "自定义")
        equal(names.displayName(make: "SONY", model: raw, customName: " \n\t"), "α7 IV")
        equal(names.displayName(make: "", model: "", customName: "自定义"), "自定义")
        equal(names.displayName(make: "SONY", model: raw, language: "en-US"), "α7 IV")

        let sample = #"{"version":1,"brands":{"test":["TEST"]},"entries":[{"brand":"test","models":["M-II"],"names":{"default":"Model II","zh-CN":"地区名称"},"sources":["https://example.com/camera"],"verifiedOn":"2026-10-28"}]}"#
        let regional = try CameraNames(data: Data(sample.utf8))
        equal(regional.displayName(make: "test", model: "M-II"), "地区名称")
        equal(regional.displayName(make: "test", model: "M-II", language: "en-US"), "Model II")
        throwsError(try CameraNames(data: Data(sample.replacingOccurrences(of: #"["M-II"]"#, with: #"["M-II","m-ii"]"#).utf8)))
        throwsError(try CameraNames(data: Data(sample.replacingOccurrences(of: #""default":"Model II""#, with: #""default":"""#).utf8)))

        let request = RenderRequest(input: "/source.tif", output: "/output.jpg", cameraMake: " SONY ",
            camera: raw, cameraNameStyle: .exif, cameraCustomName: "自定义")
        let restored = try JSONDecoder().decode(RenderRequest.self, from: JSONEncoder().encode(request))
        equal(restored.cameraMake, " SONY "); equal(restored.camera, raw)
        equal(restored.cameraNameStyle, .exif); equal(restored.cameraCustomName, "自定义")
        let legacy = #"{"version":1,"input":"/source.tif","output":"/output.jpg","theme":"white","camera":"ILCE-7M4","lens":"","exposure":"","capturedAt":"","quality":0.9}"#
        let old = try JSONDecoder().decode(RenderRequest.self, from: Data(legacy.utf8))
        equal(old.cameraNameStyle, .common); equal(old.cameraCustomName, "")
        throwsError(try JSONDecoder().decode(RenderRequest.self, from: Data(legacy.replacingOccurrences(of: #""quality":0.9"#, with: #""quality":0.9,"cameraNameStyle":"invalid""#).utf8)))
    }

    func testCameraWatermarkNames() throws {
        let names = CameraNames.bundled
        for (make, model, expected) in [
            ("SONY", "ILCE-7RM4A", "SONY α7R IVA"), ("SONY", "ILCE-9M3", "SONY α9 III"),
            ("SONY", "ILCE-1M2", "SONY α1 II"), ("SONY", "ILCE-42RM14A", "SONY α42R XIVA"),
            ("SONY", "SONY ILCE-7M4", "SONY α7 IV"), ("SONY", "SONY α7 IV", "SONY α7 IV"),
            ("Canon", "Canon EOS R5", "Canon EOS R5"), ("NIKON CORPORATION", "NIKON Z 8", "Nikon Z 8"),
            ("FUJIFILM", "X-T5", "FUJIFILM X-T5"),
            ("RICOH IMAGING COMPANY, LTD.", "PENTAX K-1", "PENTAX K-1"),
            ("RICOH IMAGING COMPANY, LTD.", "GR IIIx", "RICOH GR IIIx"),
            ("Panasonic", "DC-S5M2", "Panasonic LUMIX S5II"), ("LUMIX", "LUMIX S5II", "LUMIX S5II"),
            ("Phase One A/S", "IQ4", "Phase One A/S IQ4"),
            ("ACME", "Camera X", "ACME Camera X"), ("ACME", "acme Camera X", "acme Camera X"),
            ("Acme SONY compatible", "ILCE-7M4", "Acme SONY compatible ILCE-7M4"),
            ("SONY", "SONYish Camera", "SONY SONYish Camera"),
            ("  sony\n", "ILCE-7M4", "SONY α7 IV"), ("", "Camera X", "Camera X"),
            ("", "ILCE-7M4", "SONY ILCE-7M4"), ("SONY", "", ""), ("SONY", " \n", " \n"),
        ] {
            equal(names.watermarkName(make: make, model: model), expected)
        }
        equal(names.watermarkName(make: "SONY", model: "ILCE-7RM4A", style: .exif), "ILCE-7RM4A")
        equal(names.watermarkName(make: "", model: "ILCE-7M4", style: .exif), "ILCE-7M4")
        equal(names.watermarkName(make: "Unknown", model: "Camera X", style: .exif), "Camera X")
        equal(names.watermarkName(make: "SONY", model: "", style: .exif), "")
        equal(names.watermarkName(make: "Canon", model: "Canon EOS R5", style: .exif), "Canon EOS R5")
        equal(names.watermarkName(make: "NIKON CORPORATION", model: "NIKON Z 8", style: .exif), "NIKON Z 8")
        equal(names.watermarkName(make: "SONY", model: "ILCE-7M0"), "SONY ILCE-7M0")
        equal(names.watermarkName(make: "SONY", model: "ILCE-7M4", customName: "我的相机"), "我的相机")
        equal(names.watermarkName(make: "SONY", model: "ILCE-7M4", customName: "SONY α7 IV"), "SONY α7 IV")
        equal(names.watermarkName(make: "SONY", model: "ILCE-7M4", customName: " \n"), "SONY α7 IV")
        for brand in CameraBrand.allCases {
            let label = brand.displayName
            equal(names.watermarkName(make: brand.rawValue, model: "Camera X"), label + " Camera X")
            equal(names.watermarkName(make: brand.rawValue, model: label + " Camera X"), label + " Camera X")
            equal(names.compactWatermarkName(make: brand.rawValue, model: label + " Camera X"), "Camera X")
            equal(names.compactWatermarkName(make: brand.rawValue, model: label + " Camera X", style: .exif), "Camera X")
        }
        equal(names.compactWatermarkName(make: "SONY", model: "ILCE-7RM4A"), "α7R IVA")
        equal(names.compactWatermarkName(make: "NIKON CORPORATION", model: "NIKON Z 99"), "Z 99")
        equal(names.compactWatermarkName(make: "NIKON CORPORATION", model: "NIKON CORPORATION Z 99"), "Z 99")
        equal(names.compactWatermarkName(make: "Canon", model: "Canonical Camera X"), "Canonical Camera X")
        equal(names.compactWatermarkName(make: "Unknown", model: "Camera X"), "Camera X")
        equal(names.compactWatermarkName(make: "SONY", model: "ILCE-7M4", customName: "SONY 自定义"), "SONY 自定义")
    }

    func testSonyCameraNameRules() throws {
        let names = CameraNames.bundled
        // Representatives of the supported mirrorless families, including historical NEX cameras.
        for (model, expected) in [
            ("ILCE-1", "α1"), ("ILCE-1M2", "α1 II"),
            ("ILCE-9", "α9"), ("ILCE-9M2", "α9 II"), ("ILCE-9M3", "α9 III"),
            ("ILCE-7", "α7"), ("ILCE-7M2", "α7 II"), ("ILCE-7M3", "α7 III"), ("ILCE-7M4", "α7 IV"), ("ILCE-7M5", "α7 V"),
            ("ILCE-7R", "α7R"), ("ILCE-7RM2", "α7R II"), ("ILCE-7RM3", "α7R III"),
            ("ILCE-7RM4", "α7R IV"), ("ILCE-7RM5", "α7R V"), ("ILCE-7RM6", "α7R VI"),
            ("ILCE-7RM3A", "α7R IIIA"), ("ILCE-7RM4A", "α7R IVA"),
            ("ILCE-7S", "α7S"), ("ILCE-7SM2", "α7S II"), ("ILCE-7SM3", "α7S III"),
            ("ILCE-7C", "α7C"), ("ILCE-7CM2", "α7C II"), ("ILCE-7CR", "α7CR"),
            ("ILCE-3000", "α3000"), ("ILCE-3500", "α3500"),
            ("ILCE-5000", "α5000"), ("ILCE-5100", "α5100"),
            ("ILCE-6000", "α6000"), ("ILCE-6100", "α6100"), ("ILCE-6300", "α6300"),
            ("ILCE-6400", "α6400"), ("ILCE-6500", "α6500"), ("ILCE-6600", "α6600"), ("ILCE-6700", "α6700"),
            ("NEX-3", "NEX-3"), ("NEX-C3", "NEX-C3"), ("NEX-F3", "NEX-F3"), ("NEX-3N", "NEX-3N"),
            ("NEX-5", "NEX-5"), ("NEX-5N", "NEX-5N"), ("NEX-5R", "NEX-5R"), ("NEX-5T", "NEX-5T"),
            ("NEX-6", "NEX-6"), ("NEX-7", "NEX-7"), ("ILCE-QX1", "ILCE-QX1"),
            ("ZV-E1", "ZV-E1"), ("ZV-E10", "ZV-E10"), ("ZV-E10M2", "ZV-E10 II"),
            (" sony ilce-7cm2 ", "α7C II"), ("nex-5n", "NEX-5N"), ("zv-e10m2", "ZV-E10 II"),
            // Synthetic syntax checks establish that no per-model allowlist is required.
            ("ILCE-7M9", "α7 IX"), ("ILCE-7M10", "α7 X"),
            ("ILCE-7M4K", "α7 IVK"), ("ILCE-6800", "α6800"),
        ] {
            equal(names.displayName(make: "SONY", model: model), expected)
            equal(names.displayName(make: "SONY", model: model, style: .exif), model)
            equal(names.displayName(make: "SONY", model: model, customName: "自定义"), "自定义")
            equal(names.displayName(make: "Canon", model: model), model)
        }
        for model in ["ILCE-7M0", "ILCE-7M1", "ILCE-7M02", "ILCE-7M1000", "ILCE-7RM4AB",
                      "ILCE-7RX", "ILCE-7RSM2", "ILCE-7M4-extra", "ILCE-7M4\nextra", "ILCE-0", "ILCE-007",
                      "ILCE-7 M4", "ILCE-7M4 SONY", "SONY SONY ILCE-7M4", "NEX-VG30", "ILCA-99M2",
                      "DSLR-A900", "DSC-RX1", "ZV-1M2", "ILME-FX3", ""] {
            equal(names.displayName(make: "SONY", model: model), model)
        }
        // The Sony rule works with an empty product table and respects explicitly supplied names.
        let empty = #"{"version":1,"brands":{"sony":["SONY"]},"entries":[]}"#
        equal(try CameraNames(data: Data(empty.utf8)).displayName(make: "SONY", model: "ILCE-7M4"), "α7 IV")
        equal(try CameraNames(data: Data(empty.utf8)).displayName(make: "Unknown", model: "ILCE-7M4"), "ILCE-7M4")
    }

    func testSonyFutureCameraNameRules() throws {
        // Deliberately invented identifiers verify syntax coverage without asserting product existence.
        let cases = [
            ("ILCE-7M99", "α7 XCIX"), ("ILCE-7RM99", "α7R XCIX"),
            ("ILCE-7SM99", "α7S XCIX"), ("ILCE-7CM99", "α7C XCIX"),
            ("ILCE-7CRM99", "α7CR XCIX"), ("ILCE-7RM99A", "α7R XCIXA"),
            ("ILCE-9M99", "α9 XCIX"), ("ILCE-9M99A", "α9 XCIXA"),
            ("ILCE-1M99", "α1 XCIX"), ("ILCE-1M99A", "α1 XCIXA"),
            ("ILCE-42", "α42"), ("ILCE-42M12", "α42 XII"),
            ("ILCE-42RM14A", "α42R XIVA"), ("ILCE-42CM40", "α42C XL"),
            ("ILCE-42M90", "α42 XC"), ("ILCE-42M999", "α42 CMXCIX"),
        ]
        let empty = #"{"version":1,"brands":{"sony":["SONY"]},"entries":[]}"#
        let withoutProductTable = try CameraNames(data: Data(empty.utf8))
        for (model, expected) in cases {
            equal(CameraNames.bundled.displayName(make: "SONY", model: model), expected)
            equal(withoutProductTable.displayName(make: "SONY", model: model), expected)
            equal(withoutProductTable.displayName(make: " sony ", model: "  " + model.lowercased() + "  "), expected)
            equal(withoutProductTable.displayName(make: "SONY", model: model, style: .exif), model)
            equal(withoutProductTable.displayName(make: "SONY", model: model, customName: "自定义"), "自定义")
            equal(withoutProductTable.displayName(make: "Unknown", model: model), model)
        }
        print("Sony future syntax: \(cases.count) invented identifiers, 6 checks each")
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

    func testBlurredMetadataAndProfiles() throws {
        for style in [WatermarkStyle.detailed, .centered] {
            let input = try fixture(profile: CGColorSpace.adobeRGB1998, gps: true)
            let bitmap = directory.appendingPathComponent("blurred-\(style.rawValue).jpg")
            let jpeg = directory.appendingPathComponent("blurred-\(style.rawValue)-coefficients.jpg")
            try CardRenderer().render(RenderRequest(input: input.path, output: bitmap.path, theme: .blurred,
                camera: "ILCE-7M4", watermarkStyle: style, focalLength: "54mm"))
            try CardRenderer().render(RenderRequest(input: bitmap.path, output: jpeg.path, theme: .blurred,
                camera: "ILCE-7M4", watermarkStyle: style, focalLength: "54mm"))
            for output in [bitmap, jpeg] {
                let actual = try properties(output)
                notNil(actual[kCGImagePropertyGPSDictionary as String])
                let tiff = try unwrap(actual[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
                equal(tiff[kCGImagePropertyTIFFCopyright as String] as? String, "exifmark test copyright")
                let source = try unwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                let image = try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                equal(image.colorSpace?.name.map { $0 as String }, CGColorSpace.adobeRGB1998 as String)
            }
            let stripped = try fixture()
            try CardRenderer().render(RenderRequest(input: stripped.path, output: bitmap.path, theme: .blurred,
                camera: "SONY", capturedAt: "2026.10.28 09:41", watermarkStyle: style, focalLength: "54mm"))
            isNil(try properties(bitmap)[kCGImagePropertyGPSDictionary as String])
        }
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
    ("camera brands and legacy requests", suite.testCameraBrandResolution),
    ("camera display names and settings compatibility", suite.testCameraNames),
    ("manufacturer prefixes and deduplication", suite.testCameraWatermarkNames),
    ("Sony camera family regex rules", suite.testSonyCameraNameRules),
    ("Sony future camera syntax without a product table", suite.testSonyFutureCameraNameRules),
    ("eight orientations", suite.testAllEightOrientationsAreNormalized),
    ("metadata and AdobeRGB", suite.testAllowedMetadataAndAdobeRGBProfileSurvive),
    ("stripped GPS", suite.testStrippedGPSIsNotReintroducedByVisibleFields),
    ("lossless TIFF metadata and profile", suite.testTIFFStagingPreservesMetadataAndProfile),
    ("blurred styles preserve metadata and profiles", suite.testBlurredMetadataAndProfiles),
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
