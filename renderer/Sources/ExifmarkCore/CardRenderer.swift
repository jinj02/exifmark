import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderResult: Codable {
    public let width: Int
    public let height: Int
    public let footerHeight: Int
}

public struct CardRenderer {
    public init() {}

    @discardableResult
    public func render(_ request: RenderRequest) throws -> RenderResult {
        try request.validate()
        let inputURL = URL(fileURLWithPath: request.input)
        let outputURL = URL(fileURLWithPath: request.output)
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else { throw RenderError.input }
        let usesCoefficients = ["jpg", "jpeg"].contains(outputURL.pathExtension.lowercased())
            && CGImageSourceGetType(source).map({ $0 as String }) == UTType.jpeg.identifier
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: !usesCoefficients,
                kCGImageSourceShouldCache: !usesCoefficients,
              ] as CFDictionary) else { throw RenderError.input }

        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        if usesCoefficients {
            return try renderJPEG(request, source: source, image: image, properties: properties)
        }
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        let swap = (5...8).contains(orientation)
        let photoWidth = swap ? image.height : image.width
        let photoHeight = swap ? image.width : image.height
        // Use the oriented photo width for both layouts, including portrait images.
        let border = request.layout == .bordered ? Int((Double(photoWidth) * 0.02).rounded()) : 0
        let footerHeight = Int((Double(photoWidth) * 0.08).rounded())
        let width = photoWidth + border * 2
        let height = photoHeight + border + footerHeight
        guard width > 0, photoHeight > 0, width <= 65535, height <= 65535,
              Double(width) * Double(height) <= 200_000_000 else {
            throw RenderError.invalid("画布超出JPEG尺寸或内存限制，请缩小照片后导出。")
        }

        // Draw and encode in the upstream RGB profile. Grayscale inputs use sRGB.
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw RenderError.allocation }
        context.setFillColor(gray: request.theme == .white ? 1 : 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.saveGState()
        context.translateBy(x: CGFloat(border), y: CGFloat(footerHeight))
        context.concatenate(Self.orientationTransform(orientation, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
        if footerHeight > 0 {
            context.saveGState()
            context.translateBy(x: CGFloat(border), y: 0)
            try drawFooter(in: context, width: CGFloat(photoWidth), height: CGFloat(footerHeight), request: request, properties: properties)
            context.restoreGState()
        }
        guard let card = context.makeImage() else { throw RenderError.allocation }

        Self.updateProperties(&properties, width: width, height: height)
        let isTIFF = ["tif", "tiff"].contains(outputURL.pathExtension.lowercased())
        if isTIFF {
            // Keep the complete card lossless for Lightroom's final JPEG export.
            var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression as String] = 1 // Uncompressed RGB
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
            properties.removeValue(forKey: kCGImageDestinationLossyCompressionQuality as String)
        } else {
            properties[kCGImageDestinationLossyCompressionQuality as String] = request.quality
        }
        properties[kCGImageDestinationEmbedThumbnail as String] = false
        properties[kCGImageDestinationMergeMetadata as String] = true
        let metadata = Self.updatedMetadata(source, width: width, height: height)

        // A same-directory temporary file makes rename atomic, including replacement.
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".exifmark-\(UUID().uuidString).\(outputURL.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL, (isTIFF ? UTType.tiff : UTType.jpeg).identifier as CFString, 1, nil
        ) else { throw RenderError.output }
        CGImageDestinationAddImageAndMetadata(destination, card, metadata, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.output }
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporary in
            outputURL.withUnsafeFileSystemRepresentation { output in rename(temporary!, output!) }
        }
        guard result == 0 else { throw RenderError.write(String(cString: strerror(errno))) }
        return RenderResult(width: width, height: height, footerHeight: footerHeight)
    }

    static func orientationTransform(_ orientation: Int, width: Int, height: Int) -> CGAffineTransform {
        let w = CGFloat(width), h = CGFloat(height)
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: return .identity
        }
    }

    func drawFooter(in context: CGContext, width: CGFloat, height: CGFloat, request: RenderRequest,
                    properties: [String: Any]) throws {
        let primary: CGFloat = request.theme == .white ? 0.075 : 0.97
        let secondary: CGFloat = request.theme == .white ? 0.46 : 0.65
        let sideInset = width * 0.01
        let left = CGRect(x: sideInset, y: 0, width: width * 0.475, height: height)
        let right = CGRect(x: width - sideInset - width * 0.225, y: 0, width: width * 0.225, height: height)
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let make = request.cameraMake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (tiff?[kCGImagePropertyTIFFMake as String] as? String ?? "") : request.cameraMake
        let cameraName = CameraNames.bundled.displayName(make: make, model: request.camera,
            style: request.cameraNameStyle, customName: request.cameraCustomName)
        drawText(cameraName, in: context, frame: left, centerY: height * 0.66,
                 size: width * 0.020, weight: .emphasizedSystem, gray: primary, rightAligned: false)
        drawText(request.lens, in: context, frame: left, centerY: height * 0.34,
                 size: width * 0.0135, weight: .system, gray: secondary, rightAligned: false)
        let exposureLeft = drawText(request.exposure, in: context, frame: right, centerY: height * 0.66,
                                    size: width * 0.0155, weight: .system, gray: primary, rightAligned: true)
        let dateLeft = drawText(request.capturedAt, in: context, frame: right, centerY: height * 0.34,
                               size: width * 0.0135, weight: .system, gray: secondary, rightAligned: true)

        guard let brand = CameraBrand.resolve(
            make: make,
            model: request.camera.isEmpty ? (tiff?[kCGImagePropertyTIFFModel as String] as? String ?? "") : request.camera
        ) else { return }

        let separatorWidth = max(1, (width * 0.001).rounded())
        let separatorHeight = (height * 0.42).rounded()
        let textLeft = [exposureLeft, dateLeft].compactMap { $0 }.min() ?? right.minX
        // Anchor the brand group to the visible text, including its fitted font size.
        let separatorX = (textLeft - width * 0.012 - separatorWidth).rounded()
        context.setFillColor(gray: secondary, alpha: 1)
        context.fill(CGRect(x: separatorX,
                            y: ((height - separatorHeight) / 2).rounded(),
                            width: separatorWidth, height: separatorHeight))

        let name = "\(brand.rawValue)-\(request.theme == .white ? "black" : "white")"
        // Resolve beside the executable so distribution never relies on a build-machine path.
        guard let executable = Bundle.main.executableURL,
              let resources = Bundle(url: executable.deletingLastPathComponent()
                .appendingPathComponent("ExifmarkRenderer_ExifmarkCore.bundle")),
              let url = resources.url(forResource: name, withExtension: "pdf"),
              let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
            throw RenderError.logo
        }
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw RenderError.logo }
        let scale = min(width * 0.112 / bounds.width, height * 0.52 / bounds.height)
        let logoWidth = bounds.width * scale
        let logoHeight = bounds.height * scale
        let rect = CGRect(x: separatorX - width * 0.018 - logoWidth, y: (height - logoHeight) / 2,
                          width: logoWidth, height: logoHeight)
        context.saveGState()
        // Scale explicitly: CGPDFPage's fit transform does not enlarge small SVG view boxes.
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / bounds.width, y: rect.height / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    @discardableResult
    private func drawText(_ text: String, in context: CGContext, frame: CGRect, centerY: CGFloat,
                          size: CGFloat, weight: CTFontUIFontType, gray: CGFloat, rightAligned: Bool) -> CGFloat? {
        let text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let color = CGColor(gray: gray, alpha: 1)
        func line(at size: CGFloat) -> CTLine {
            let font = CTFontCreateUIFontForLanguage(weight, size, nil)!
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            return CTLineCreateWithAttributedString(string)
        }
        var fitted = line(at: size)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(fitted, nil, nil, nil))
        if naturalWidth > frame.width {
            let fittedSize = max(size * 0.75, size * frame.width / naturalWidth)
            fitted = line(at: fittedSize)
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateUIFontForLanguage(weight, fittedSize, nil)!,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
            fitted = CTLineCreateTruncatedLine(fitted, Double(frame.width), .end, token) ?? token
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(fitted, &ascent, &descent, nil))
        let textX = rightAligned ? frame.maxX - lineWidth : frame.minX
        context.saveGState()
        context.clip(to: frame)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: textX, y: centerY - (ascent - descent) / 2)
        CTLineDraw(fitted, context)
        context.restoreGState()
        let inkBounds = CTLineGetBoundsWithOptions(fitted, .useGlyphPathBounds)
        guard !inkBounds.isNull, inkBounds.minX.isFinite else { return nil }
        return max(frame.minX, textX + inkBounds.minX)
    }

    private static func updateProperties(_ properties: inout [String: Any], width: Int, height: Int) {
        properties[kCGImagePropertyPixelWidth as String] = width
        properties[kCGImagePropertyPixelHeight as String] = height
        properties[kCGImagePropertyOrientation as String] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = width
            exif[kCGImagePropertyExifPixelYDimension as String] = height
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
    }

    static func updatedMetadata(_ source: CGImageSource, width: Int, height: Int,
                                orientation: Int = 1) -> CGImageMetadata? {
        guard let original = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let metadata = CGImageMetadataCreateMutableCopy(original) else { return nil }
        // Update existing XMP technical fields without reintroducing catalog metadata.
        for (path, value) in [("tiff:Orientation", orientation), ("tiff:ImageWidth", width), ("tiff:ImageLength", height),
                              ("exif:PixelXDimension", width), ("exif:PixelYDimension", height)] {
            if CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) != nil {
                CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFNumber)
            }
        }
        return metadata
    }
}
