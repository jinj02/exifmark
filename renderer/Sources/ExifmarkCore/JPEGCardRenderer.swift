import CExifmarkJPEG
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CardRenderer {
    func renderJPEG(_ request: RenderRequest, source: CGImageSource, image: CGImage,
                    properties: [String: Any]) throws -> RenderResult {
        var info = ExifmarkJPEGInfo()
        var message = [CChar](repeating: 0, count: 512)
        guard exifmark_jpeg_read_info(request.input, &info, &message, message.count) != 0 else {
            throw RenderError.invalid("无法读取JPEG压缩参数：\(String(cString: message))")
        }
        let orientationValue = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        let orientation = (1...8).contains(orientationValue) ? orientationValue : 1
        let swap = (5...8).contains(orientation)
        let photoWidth = Int(swap ? info.height : info.width)
        let mcuWidth = Int(swap ? info.mcu_height : info.mcu_width)
        let mcuHeight = Int(swap ? info.mcu_width : info.mcu_height)
        func aligned(_ value: Int, to block: Int) -> Int { (value + block - 1) / block * block }
        let paddedWidth = aligned(Int(info.width), to: Int(info.mcu_width))
        let paddedHeight = aligned(Int(info.height), to: Int(info.mcu_height))
        let displayPhotoWidth = swap ? paddedHeight : paddedWidth
        let displayPhotoHeight = swap ? paddedWidth : paddedHeight
        let nominalBorder = Int((Double(photoWidth) * 0.02).rounded())
        let borderX = request.layout == .bordered ? aligned(nominalBorder, to: mcuWidth) : 0
        let borderY = request.layout == .bordered ? aligned(nominalBorder, to: mcuHeight) : 0
        let footerHeight = aligned(max(1, Int((Double(photoWidth) * 0.08).rounded())), to: mcuHeight)
        let width = displayPhotoWidth + borderX * 2
        let height = displayPhotoHeight + borderY + footerHeight
        guard width <= 65500, height <= 65500, Double(width) * Double(height) <= 200_000_000 else {
            throw RenderError.invalid("画布超出JPEG尺寸或内存限制，请缩小照片后导出。")
        }

        // Retain EXIF orientation so flipped/rotated photos keep every original coefficient.
        // Padding exposes the final partial blocks without cropping or re-quantizing them.
        let rawWidth = swap ? height : width
        let rawHeight = swap ? width : height
        let transform = Self.orientationTransform(orientation, width: rawWidth, height: rawHeight).inverted()
        let photoRect = CGRect(x: borderX, y: footerHeight, width: displayPhotoWidth, height: displayPhotoHeight)
            .applying(transform)
        let photoX = Int(photoRect.minX.rounded())
        let photoY = rawHeight - Int(photoRect.maxY.rounded())
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: rawWidth, height: rawHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let pixels = context.data else { throw RenderError.allocation }
        context.setFillColor(gray: request.theme == .white ? 1 : 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: rawWidth, height: rawHeight))
        context.concatenate(transform)
        context.translateBy(x: CGFloat(borderX), y: 0)
        try drawFooter(in: context, width: CGFloat(photoWidth), height: CGFloat(footerHeight), request: request)

        let outputURL = URL(fileURLWithPath: request.output)
        let directory = outputURL.deletingLastPathComponent()
        let coefficientURL = directory.appendingPathComponent(".exifmark-\(UUID().uuidString)-coefficients.jpg")
        let temporaryURL = directory.appendingPathComponent(".exifmark-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: coefficientURL)
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        guard exifmark_jpeg_compose(request.input, coefficientURL.path,
                                    pixels.assumingMemoryBound(to: UInt8.self), Int32(rawWidth), Int32(rawHeight),
                                    context.bytesPerRow, Int32(photoX), Int32(photoY), &message, message.count) != 0 else {
            throw RenderError.invalid("无法拼接JPEG压缩数据：\(String(cString: message))")
        }

        // ImageIO's lossless copy API updates metadata without encoding any image samples.
        guard let composed = CGImageSourceCreateWithURL(coefficientURL as CFURL, nil),
              let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
              ) else { throw RenderError.output }
        var options: [String: Any] = [:]
        if let metadata = Self.updatedMetadata(source, width: rawWidth, height: rawHeight, orientation: orientation) {
            options[kCGImageDestinationMetadata as String] = metadata
            options[kCGImageDestinationMergeMetadata as String] = true
        }
        var copyError: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, composed, options as CFDictionary, &copyError) else {
            let reason = copyError?.takeRetainedValue().localizedDescription ?? "无法无损更新JPEG元数据。"
            throw RenderError.write(reason)
        }
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporary in
            outputURL.withUnsafeFileSystemRepresentation { output in rename(temporary!, output!) }
        }
        guard result == 0 else { throw RenderError.write(String(cString: strerror(errno))) }
        return RenderResult(width: width, height: height, footerHeight: footerHeight)
    }
}
