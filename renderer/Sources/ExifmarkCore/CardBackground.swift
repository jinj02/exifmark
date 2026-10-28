import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A small, oriented background shared by the bitmap and JPEG coefficient paths.
struct CardBackground {
    let image: CGImage?
    let canvas: CGRect

    init(source: CGImageSource, theme: Theme, width: Int, height: Int,
         photoWidth: Int, colorSpace: CGColorSpace) throws {
        canvas = CGRect(x: 0, y: 0, width: width, height: height)
        guard theme == .blurred else { image = nil; return }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { throw RenderError.input }
        let scale = min(1, 2048 / CGFloat(max(width, height)))
        let extent = CGRect(x: 0, y: 0, width: max(1, Int(CGFloat(width) * scale)),
                            height: max(1, Int(CGFloat(height) * scale)))
        let fillScale = max(extent.width / CGFloat(thumbnail.width), extent.height / CGFloat(thumbnail.height))
        let sourceImage = CIImage(cgImage: thumbnail).transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        let centered = sourceImage.transformed(by: CGAffineTransform(
            translationX: (extent.width - sourceImage.extent.width) / 2,
            y: (extent.height - sourceImage.extent.height) / 2))
        let blurred = centered.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: CGFloat(photoWidth) * 0.02 * scale,
        ]).cropped(to: extent)
        let renderer = CIContext(options: [.cacheIntermediates: false])
        guard let result = renderer.createCGImage(blurred, from: extent, format: .RGBA8, colorSpace: colorSpace)
            ?? CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
                .createCGImage(blurred, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw RenderError.invalid("无法生成原图模糊背景。")
        }
        image = result
    }

    func draw(in context: CGContext, theme: Theme) {
        if let image {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(image, in: canvas)
            context.restoreGState()
        } else {
            context.setFillColor(gray: theme == .white ? 1 : 0, alpha: 1)
            context.fill(canvas)
        }
    }

    /// Alpha weights select the actual text, divider and logo footprint before any ink is drawn.
    func foreground(width: CGFloat, height: CGFloat, offsetX: CGFloat,
                    drawMask: (CGContext) throws -> Void) throws -> CGFloat {
        guard let image else { return 0 }
        let scale = min(1, 2048 / width)
        let sampleWidth = max(1, Int(ceil(width * scale)))
        let sampleHeight = max(1, Int(ceil(height * scale)))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func context() throws -> CGContext {
            guard let result = CGContext(data: nil, width: sampleWidth, height: sampleHeight,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { throw RenderError.allocation }
            result.scaleBy(x: scale, y: scale)
            return result
        }
        let mask = try context()
        try drawMask(mask)
        let background = try context()
        background.interpolationQuality = .high
        background.draw(image, in: canvas.offsetBy(dx: -offsetX, dy: 0))
        guard let maskData = mask.data, let backgroundData = background.data else { throw RenderError.allocation }
        let alpha = maskData.assumingMemoryBound(to: UInt8.self)
        let rgb = backgroundData.assumingMemoryBound(to: UInt8.self)
        let linear = (0...255).map { value -> Double in
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var luminance = 0.0, weight = 0.0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let a = Double(alpha[y * mask.bytesPerRow + x * 4 + 3]) / 255
                guard a > 0 else { continue }
                let pixel = y * background.bytesPerRow + x * 4
                luminance += a * (0.2126 * linear[Int(rgb[pixel])] + 0.7152 * linear[Int(rgb[pixel + 1])]
                                 + 0.0722 * linear[Int(rgb[pixel + 2])])
                weight += a
            }
        }
        guard weight > 0 else { return 0 }
        let mean = luminance / weight
        return (mean + 0.05) / 0.05 >= 1.05 / (mean + 0.05) ? 0 : 1
    }
}
