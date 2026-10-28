#!/usr/bin/env swift
// Generate parameter-only README headers using the plugin's actual renderer.
// Run `scripts/build.sh`, then `swift scripts/render-readme-header.swift`.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let work = root.appendingPathComponent(".build/readme-header")
let output = root.appendingPathComponent("docs")
let width = 2400, height = 192

func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ReadmeHeader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
    }
    return image
}

func save(_ image: CGImage, to url: URL, type: CFString) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
// A one-pixel input allows the normal rendering path to produce only a footer.
let placeholder = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
placeholder.setFillColor(gray: 1, alpha: 1)
placeholder.fill(CGRect(x: 0, y: 0, width: width, height: 1))
let input = work.appendingPathComponent("blank.tif")
save(placeholder.makeImage()!, to: input, type: UTType.tiff.identifier as CFString)
let original = try load(root.appendingPathComponent("docs/logo.png"))
// Trim the existing transparent margin; preserve the supplied symbol's alpha.
guard let icon = original.cropping(to: CGRect(x: 16, y: 41, width: 384, height: 329)) else {
    fatalError("Cannot crop the supplied logo")
}
for (theme, name) in [("white", "light"), ("black", "dark")] {
    let staged = work.appendingPathComponent("footer-\(theme).tif")
    let request: [String: Any] = [
        "version": 1, "input": input.path, "output": staged.path,
        "theme": theme, "layout": "bottomOnly", "cameraMake": "SONY",
        "camera": "SONY α7R VI", "lens": "FE 24-70mm F2.8 GM II · 35mm",
        "exposure": "f/8 · 1/250s · ISO 100", "capturedAt": "2026.10.18 07:24", "quality": 1,
    ]
    let requestURL = work.appendingPathComponent("request-\(theme).json")
    try JSONSerialization.data(withJSONObject: request, options: [.prettyPrinted, .sortedKeys]).write(to: requestURL)
    let renderer = Process()
    renderer.executableURL = root.appendingPathComponent("exifmark.lrplugin/bin/exifmark-render")
    renderer.arguments = ["--request", requestURL.path]
    try renderer.run()
    renderer.waitUntilExit()
    precondition(renderer.terminationStatus == 0, "Build the renderer with scripts/build.sh first")
    let card = try load(staged)
    let footer = card.cropping(to: CGRect(x: 0, y: 1, width: width, height: height))!
    precondition(footer.width == width && footer.height == height)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: height))
    // Omit the camera wordmark from README artwork while preserving its divider.
    context.setFillColor(gray: theme == "white" ? 1 : 0, alpha: 1)
    context.fill(CGRect(x: 1656, y: 0, width: 312, height: height))
    let ink: CGFloat = theme == "white" ? 0.075 : 0.97
    let iconRect = CGRect(x: 900, y: 51, width: 105, height: 90)
    context.saveGState()
    context.clip(to: iconRect, mask: icon)
    context.setFillColor(gray: ink, alpha: 1)
    context.fill(iconRect)
    context.restoreGState()
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 84, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "exifmark", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: ink, alpha: 1),
    ]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: 1034, y: (CGFloat(height) - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, context)
    let image = context.makeImage()!
    let url = output.appendingPathComponent("readme-header-\(name)-v2.png")
    save(image, to: url, type: UTType.png.identifier as CFString)
    print(url.path)
}
