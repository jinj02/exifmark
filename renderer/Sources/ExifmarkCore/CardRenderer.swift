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
        // Proportions follow the short edge so landscape and portrait cards share one visual scale.
        let unit = Self.unit(photoWidth: photoWidth, photoHeight: photoHeight)
        let border = Self.border(unit: unit, request: request)
        let footerHeight = Self.footerHeight(unit: unit)
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
        let background = try CardBackground(source: source, theme: request.theme, width: width, height: height,
                                            unit: unit, colorSpace: colorSpace)
        let footer = FooterFrame(width: CGFloat(photoWidth), height: CGFloat(footerHeight), unit: unit,
                                 inset: Self.textInset(unit: unit, request: request), offsetX: CGFloat(border))
        let ink = try footerInk(footer, request: request, properties: properties, background: background)
        background.draw(in: context, theme: request.theme, adaptiveInk: ink.adaptive,
                        photoRect: border > 0 ? CGRect(x: border, y: footerHeight, width: photoWidth, height: photoHeight)
                                              : nil, unit: unit)
        context.interpolationQuality = .none
        context.saveGState()
        context.translateBy(x: CGFloat(border), y: CGFloat(footerHeight))
        context.concatenate(Self.orientationTransform(orientation, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
        if footerHeight > 0 {
            context.saveGState()
            context.translateBy(x: CGFloat(border), y: 0)
            try drawFooterContents(in: context, footer: footer, request: request, properties: properties, ink: ink)
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

    // MARK: - Card proportions

    /// The oriented short edge drives borders, footer height and type sizes.
    static func unit(photoWidth: Int, photoHeight: Int) -> CGFloat {
        CGFloat(max(1, min(photoWidth, photoHeight)))
    }

    /// White and black frames use 3% of the short edge; the blurred frame needs 5% to read as glass.
    static func border(unit: CGFloat, request: RenderRequest) -> Int {
        guard request.layout == .bordered else { return 0 }
        return Int((unit * (request.theme == .blurred ? 0.05 : 0.03)).rounded())
    }

    static func footerHeight(unit: CGFloat) -> Int {
        max(1, Int((unit * 0.12).rounded()))
    }

    /// Bordered cards align text with the photo edges; edge-to-edge cards keep a border-sized inset.
    static func textInset(unit: CGFloat, request: RenderRequest) -> CGFloat {
        request.layout == .bordered ? 0 : (unit * 0.03).rounded()
    }

    // MARK: - Footer

    struct FooterFrame {
        let width: CGFloat
        let height: CGFloat
        let unit: CGFloat
        let inset: CGFloat
        let offsetX: CGFloat
    }

    struct FooterInk {
        let primary: CGColor
        let secondary: CGColor
        let whiteLogo: Bool
        /// Blurred cards report the chosen ink (0 black, 1 white) so the backdrop can be tinted to match.
        let adaptive: CGFloat?

        static let mask = FooterInk(primary: CGColor(gray: 1, alpha: 1), secondary: CGColor(gray: 1, alpha: 1),
                                    whiteLogo: true, adaptive: nil)
    }

    private struct TextStyle {
        let size: CGFloat
        let weight: CGFloat
        let tracking: CGFloat
        let tabular: Bool
    }

    func footerInk(_ footer: FooterFrame, request: RenderRequest, properties: [String: Any],
                   background: CardBackground) throws -> FooterInk {
        switch request.theme {
        case .white:
            return FooterInk(primary: CGColor(gray: 0.08, alpha: 1), secondary: CGColor(gray: 0.40, alpha: 1),
                             whiteLogo: false, adaptive: nil)
        case .black:
            return FooterInk(primary: CGColor(gray: 0.96, alpha: 1), secondary: CGColor(gray: 0.70, alpha: 1),
                             whiteLogo: true, adaptive: nil)
        case .blurred:
            let ink = try background.foreground(width: footer.width, height: footer.height,
                                                offsetX: footer.offsetX) { mask in
                try drawFooterContents(in: mask, footer: footer, request: request, properties: properties,
                                       ink: .mask)
            }
            return FooterInk(primary: CGColor(gray: ink, alpha: 1),
                             secondary: CGColor(gray: ink, alpha: ink == 1 ? 0.78 : 0.68),
                             whiteLogo: ink == 1, adaptive: ink)
        }
    }

    func drawFooterContents(in context: CGContext, footer: FooterFrame, request: RenderRequest,
                            properties: [String: Any], ink: FooterInk) throws {
        let u = footer.unit, width = footer.width, height = footer.height
        let contentWidth = width - footer.inset * 2
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let make = request.cameraMake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (tiff?[kCGImagePropertyTIFFMake as String] as? String ?? "") : request.cameraMake
        let brand = CameraBrand.resolve(make: make,
            model: request.camera.isEmpty ? (tiff?[kCGImagePropertyTIFFModel as String] as? String ?? "") : request.camera)

        let model = TextStyle(size: u * 0.029, weight: 0.3, tracking: 0, tabular: false)
        let parameters = TextStyle(size: u * 0.025, weight: 0.23, tracking: 0.005, tabular: true)
        let detail = TextStyle(size: u * 0.020, weight: 0, tracking: 0.015, tabular: true)
        // Two rows read as one block centred in the footer.
        let upperY = height * 0.635, lowerY = height * 0.365

        if request.watermarkStyle == .centered {
            let cameraName = CameraNames.bundled.compactWatermarkName(make: make, model: request.camera,
                style: request.cameraNameStyle, customName: request.cameraCustomName)
            let page = try brand.map { try logoPage(brand: $0, white: ink.whiteLogo) }
            let bounds = page?.getBoxRect(.mediaBox) ?? .zero
            let scale = page == nil ? 0 : min(u * 0.12 / bounds.width, height * 0.28 / bounds.height)
            let logoWidth = bounds.width * scale, logoHeight = bounds.height * scale
            let gap = page != nil && !cameraName.isEmpty ? u * 0.018 : 0
            let available = contentWidth * 0.8 - logoWidth - gap
            let cameraLine = fittedLine(cameraName, width: available, style: model, color: ink.primary)
            let cameraWidth = CGFloat(CTLineGetTypographicBounds(cameraLine, nil, nil, nil))
            let startX = (width - logoWidth - gap - cameraWidth) / 2
            if let page {
                drawLogo(page, in: context, rect: CGRect(x: startX, y: upperY - logoHeight / 2,
                                                       width: logoWidth, height: logoHeight))
            }
            drawText(cameraName, in: context,
                     frame: CGRect(x: startX + logoWidth + gap, y: 0, width: max(cameraWidth, 1), height: height),
                     centerY: upperY, style: model, color: ink.primary, preparedLine: cameraLine)
            let values = [request.focalLength, request.exposure].filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.joined(separator: " · ")
            drawText(values, in: context,
                     frame: CGRect(x: footer.inset + contentWidth * 0.1, y: 0, width: contentWidth * 0.8, height: height),
                     centerY: lowerY, style: detail, color: ink.secondary, alignment: .center)
            return
        }

        let left = CGRect(x: footer.inset, y: 0, width: contentWidth * 0.475, height: height)
        let right = CGRect(x: width - footer.inset - contentWidth * 0.26, y: 0,
                           width: contentWidth * 0.26, height: height)
        let cameraName = CameraNames.bundled.watermarkName(make: make, model: request.camera,
            style: request.cameraNameStyle, customName: request.cameraCustomName)
        drawText(cameraName, in: context, frame: left, centerY: upperY, style: model, color: ink.primary)
        drawText(request.lens, in: context, frame: left, centerY: lowerY, style: detail, color: ink.secondary)
        let exposureLeft = drawText(request.exposure, in: context, frame: right, centerY: upperY,
                                    style: parameters, color: ink.primary, alignment: .right)
        let dateLeft = drawText(request.capturedAt, in: context, frame: right, centerY: lowerY,
                                style: detail, color: ink.secondary, alignment: .right)

        guard let brand else { return }

        let separatorWidth = max(1, (u * 0.0012).rounded())
        let separatorHeight = (height * 0.40).rounded()
        let textLeft = [exposureLeft, dateLeft].compactMap { $0 }.min() ?? right.minX
        // Anchor the brand group to the visible text, including its fitted font size.
        let separatorX = (textLeft - u * 0.018 - separatorWidth).rounded()
        context.setFillColor(ink.secondary)
        context.fill(CGRect(x: separatorX, y: ((height - separatorHeight) / 2).rounded(),
                            width: separatorWidth, height: separatorHeight))

        let page = try logoPage(brand: brand, white: ink.whiteLogo)
        let bounds = page.getBoxRect(.mediaBox)
        let scale = min(u * 0.15 / bounds.width, height * 0.38 / bounds.height)
        let logoWidth = bounds.width * scale
        let logoHeight = bounds.height * scale
        let rect = CGRect(x: separatorX - u * 0.024 - logoWidth, y: (height - logoHeight) / 2,
                          width: logoWidth, height: logoHeight)
        drawLogo(page, in: context, rect: rect)
    }

    private func logoPage(brand: CameraBrand, white: Bool) throws -> CGPDFPage {
        let name = "\(brand.rawValue)-\(white ? "white" : "black")"
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
        return page
    }

    private func drawLogo(_ page: CGPDFPage, in context: CGContext, rect: CGRect) {
        let bounds = page.getBoxRect(.mediaBox)
        context.saveGState()
        // Scale explicitly: CGPDFPage's fit transform does not enlarge small SVG view boxes.
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / bounds.width, y: rect.height / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private enum Alignment { case left, right, center }

    @discardableResult
    private func drawText(_ text: String, in context: CGContext, frame: CGRect, centerY: CGFloat,
                          style: TextStyle, color: CGColor, alignment: Alignment = .left,
                          preparedLine: CTLine? = nil) -> CGFloat? {
        guard !text.isEmpty else { return nil }
        let fitted = preparedLine ?? fittedLine(text, width: frame.width, style: style, color: color)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(fitted, nil, nil, nil))
        let textX: CGFloat
        switch alignment {
        case .left: textX = frame.minX
        case .right: textX = frame.maxX - lineWidth
        case .center: textX = frame.midX - lineWidth / 2
        }
        // Centre on cap height so rows sit optically level with logos and dividers.
        let capHeight = Self.lineFont(fitted).map { CTFontGetCapHeight($0) } ?? style.size * 0.7
        context.saveGState()
        context.clip(to: frame)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: textX, y: centerY - capHeight / 2)
        CTLineDraw(fitted, context)
        context.restoreGState()
        let inkBounds = CTLineGetBoundsWithOptions(fitted, .useGlyphPathBounds)
        guard !inkBounds.isNull, inkBounds.minX.isFinite else { return nil }
        return max(frame.minX, textX + inkBounds.minX)
    }

    private static func lineFont(_ line: CTLine) -> CTFont? {
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
              let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { return nil }
        return (value as! CTFont)
    }

    /// SF Pro at an explicit weight, optionally with tabular figures for aligned exposure values.
    private static func font(_ style: TextStyle, size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        var attributes: [CFString: Any] = [kCTFontTraitsAttribute: [kCTFontWeightTrait: style.weight]]
        if style.tabular {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
            ]]
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                  attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private func fittedLine(_ text: String, width: CGFloat, style: TextStyle, color: CGColor) -> CTLine {
        let text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
        func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            [
                NSAttributedString.Key(kCTFontAttributeName as String): Self.font(style, size: size),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTKernAttributeName as String): size * style.tracking,
            ]
        }
        func line(at size: CGFloat) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes(size)))
        }
        var fitted = line(at: style.size)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(fitted, nil, nil, nil))
        if naturalWidth > width {
            let fittedSize = max(style.size * 0.75, style.size * width / naturalWidth)
            fitted = line(at: fittedSize)
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…",
                                                                            attributes: attributes(fittedSize)))
            fitted = CTLineCreateTruncatedLine(fitted, Double(width), .end, token) ?? token
        }
        return fitted
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
