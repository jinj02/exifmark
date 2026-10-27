import Foundation

public enum Theme: String, Codable {
    case white, black
}

public enum Layout: String, Codable {
    case bordered, bottomOnly
}

public struct RenderRequest: Codable {
    public var version: Int
    public var input: String
    public var output: String
    public var theme: Theme
    public var layout: Layout
    public var camera: String
    public var lens: String
    public var exposure: String
    public var capturedAt: String
    // JPEG inputs retain their own quantization tables; this value applies to other inputs.
    public var quality: Double

    public init(input: String, output: String, theme: Theme = .white, layout: Layout = .bordered,
                camera: String = "", lens: String = "", exposure: String = "",
                capturedAt: String = "", quality: Double = 0.9) {
        self.version = 1
        self.input = input
        self.output = output
        self.theme = theme
        self.layout = layout
        self.camera = camera
        self.lens = lens
        self.exposure = exposure
        self.capturedAt = capturedAt
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey {
        case version, input, output, theme, layout, camera, lens, exposure, capturedAt, quality
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        input = try values.decode(String.self, forKey: .input)
        output = try values.decode(String.self, forKey: .output)
        theme = try values.decode(Theme.self, forKey: .theme)
        layout = try values.decodeIfPresent(Layout.self, forKey: .layout) ?? .bordered
        camera = try values.decode(String.self, forKey: .camera)
        lens = try values.decode(String.self, forKey: .lens)
        exposure = try values.decode(String.self, forKey: .exposure)
        capturedAt = try values.decode(String.self, forKey: .capturedAt)
        quality = try values.decode(Double.self, forKey: .quality)
    }

    public func validate() throws {
        guard version == 1 else { throw RenderError.invalid("不支持的渲染请求版本。") }
        guard quality.isFinite, (0...1).contains(quality) else {
            throw RenderError.invalid("JPEG质量必须在0到1之间。")
        }
        for path in [input, output] {
            guard path.hasPrefix("/"), !path.utf8.contains(0) else {
                throw RenderError.invalid("图片路径必须是有效的绝对路径。")
            }
        }
        let source = URL(fileURLWithPath: input).resolvingSymlinksInPath().standardizedFileURL
        let destination = URL(fileURLWithPath: output).resolvingSymlinksInPath().standardizedFileURL
        guard source != destination else { throw RenderError.invalid("输入和输出路径必须不同。") }
        guard ["jpg", "jpeg", "tif", "tiff"].contains(destination.pathExtension.lowercased()) else {
            throw RenderError.invalid("输出文件需要使用.tif、.tiff、.jpg或.jpeg扩展名。")
        }
    }
}

public enum RenderError: Error, LocalizedError {
    case invalid(String)
    case input
    case allocation
    case logo
    case output
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .input: return "无法读取输入图片，文件可能损坏或格式不受支持。"
        case .allocation: return "图片过大或可用内存不足，无法创建画布。"
        case .logo: return "SONY字标资源缺失或损坏，请重新安装完整插件。"
        case .output: return "无法编码图像，请检查导出目录和可用空间。"
        case .write(let message): return "无法保存图像：\(message)"
        }
    }
}
