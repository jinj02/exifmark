import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct JPEGInstallRequest: Codable {
    public var input: String
    public var output: String

    public init(input: String, output: String) {
        self.input = input
        self.output = output
    }

    public func install() throws {
        try RenderRequest(input: input, output: output).validate()
        let sourceURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)
        guard ["jpg", "jpeg"].contains(outputURL.pathExtension.lowercased()),
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetType(source).map({ $0 as String }) == UTType.jpeg.identifier else {
            throw RenderError.invalid("最终成片必须为LrC生成的JPEG。")
        }
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".exifmark-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do { try FileManager.default.copyItem(at: sourceURL, to: temporaryURL) }
        catch { throw RenderError.write(error.localizedDescription) }
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporary in
            outputURL.withUnsafeFileSystemRepresentation { output in rename(temporary!, output!) }
        }
        guard result == 0 else { throw RenderError.write(String(cString: strerror(errno))) }
    }
}
