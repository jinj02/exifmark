#!/usr/bin/env swift
// Generate the README close-up with the plugin renderer.
// Run `scripts/build.sh`, then `swift scripts/render-readme-detail.swift`.
// Each strip is a lossless crop of the actual footer, with no retouching.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let work = root.appendingPathComponent(".build/readme-detail")
let output = root.appendingPathComponent("docs/readme-detail-crop.png")
let width = 2400, photoHeight = 1600, gap = 24

struct Example {
    let id, make, camera, lens, focalLength, exposure, capturedAt, theme: String
}

let examples = [
    // Full-frame Sony E, ultra-wide zoom; choose the Sony E version.
    // https://www.sigma-global.com/en/lenses/a019_14_24_28/
    Example(id: "sony", make: "SONY", camera: "ILCE-7RM5",
            lens: "SIGMA 14-24mm F2.8 DG DN | Art · 14mm", focalLength: "14mm",
            exposure: "f/8 · 1/125s · ISO 100", capturedAt: "2026.10.18 06:42", theme: "white"),
    // Fujifilm X, APS-C standard prime (50mm equivalent).
    // https://www.fujifilm-x.com/global/products/lenses/xf33mmf14-r-lm-wr/specifications/
    Example(id: "fujifilm", make: "FUJIFILM", camera: "X-T5",
            lens: "XF 33mm F1.4 R LM WR · 33mm", focalLength: "33mm",
            exposure: "f/1.4 · 1/250s · ISO 400", capturedAt: "2026.10.18 09:16", theme: "black"),
    // Hasselblad XCD, medium-format standard prime (43mm equivalent).
    // https://master.hasselblad.com/x-system/lenses/xcd-55v/
    Example(id: "hasselblad", make: "Hasselblad", camera: "X2D 100C",
            lens: "XCD 2,5/55V · 55mm", focalLength: "55mm",
            exposure: "f/5.6 · 1/250s · ISO 64", capturedAt: "2026.10.18 14:28", theme: "white"),
    // Full-frame Nikon Z, wide-to-telephoto zoom; choose the Nikon Z version.
    // https://www.tamron.com/global/consumer/lenses/a058/
    Example(id: "nikon", make: "NIKON CORPORATION", camera: "NIKON Z 8",
            lens: "TAMRON 35-150mm F/2-2.8 Di III VXD · 85mm", focalLength: "85mm",
            exposure: "f/2.8 · 1/500s · ISO 200", capturedAt: "2026.10.18 16:35", theme: "black"),
    // Full-frame Canon RF, telephoto zoom; native EOS R5 support.
    // https://asia.canon/en/support/8204838100
    Example(id: "canon", make: "Canon", camera: "Canon EOS R5",
            lens: "RF 70-200mm F2.8 L IS USM · 200mm", focalLength: "200mm",
            exposure: "f/2.8 · 1/1000s · ISO 800", capturedAt: "2026.10.18 17:52", theme: "white"),
]

func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ReadmeDetail", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
    }
    return image
}

func save(_ image: CGImage, to url: URL, type: CFString) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot save \(url.path)")
}

func canvas(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

struct RenderResult: Decodable {
    let width, height, footerHeight: Int
}

try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
// A normal landscape input preserves the renderer's short-edge-based proportions.
let placeholder = canvas(width: width, height: photoHeight)
placeholder.setFillColor(gray: 1, alpha: 1)
placeholder.fill(CGRect(x: 0, y: 0, width: width, height: photoHeight))
let input = work.appendingPathComponent("blank.tif")
save(placeholder.makeImage()!, to: input, type: UTType.tiff.identifier as CFString)

var footers: [CGImage] = []
for example in examples {
    let staged = work.appendingPathComponent("\(example.id).tif")
    let request: [String: Any] = [
        "version": 1, "input": input.path, "output": staged.path,
        "theme": example.theme, "layout": "bottomOnly", "watermarkStyle": "detailed",
        "cameraMake": example.make, "camera": example.camera, "cameraNameStyle": "common",
        "lens": example.lens, "focalLength": example.focalLength,
        "exposure": example.exposure, "capturedAt": example.capturedAt, "quality": 1,
    ]
    let requestURL = work.appendingPathComponent("\(example.id).json")
    try JSONSerialization.data(withJSONObject: request, options: [.prettyPrinted, .sortedKeys]).write(to: requestURL)
    let renderer = Process()
    renderer.executableURL = root.appendingPathComponent("exifmark.lrplugin/bin/exifmark-render")
    renderer.arguments = ["--request", requestURL.path]
    let pipe = Pipe()
    renderer.standardOutput = pipe
    try renderer.run()
    let resultData = pipe.fileHandleForReading.readDataToEndOfFile()
    renderer.waitUntilExit()
    precondition(renderer.terminationStatus == 0, "Build the renderer with scripts/build.sh first")
    let result = try JSONDecoder().decode(RenderResult.self, from: resultData)
    let card = try load(staged)
    precondition(result.width == width && result.height == photoHeight + result.footerHeight)
    precondition(card.width == result.width && card.height == result.height && result.footerHeight > 1)
    let footer = card.cropping(to: CGRect(x: 0, y: photoHeight, width: width, height: result.footerHeight))!
    save(footer, to: work.appendingPathComponent("\(example.id)-footer.png"),
         type: UTType.png.identifier as CFString)
    footers.append(footer)
}

let height = footers.reduce(0) { $0 + $1.height } + gap * (footers.count - 1)
let composite = canvas(width: width, height: height)
composite.setFillColor(gray: 0.9, alpha: 1)
composite.fill(CGRect(x: 0, y: 0, width: width, height: height))
composite.interpolationQuality = .none
var top = height
for footer in footers {
    top -= footer.height
    composite.draw(footer, in: CGRect(x: 0, y: top, width: width, height: footer.height))
    top -= gap
}
save(composite.makeImage()!, to: output, type: UTType.png.identifier as CFString)
print(output.path)
