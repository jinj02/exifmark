import Foundation

public enum CameraNameStyle: String, Codable {
    case common, exif
}

/// Product data and family parsers are independent of rendering and logo recognition.
public struct CameraNames {
    private struct Catalog: Decodable {
        let version: Int
        let brands: [String: [String]]
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let brand: String
        let models: [String]
        let names: [String: String]
        let sources: [URL]
        let verifiedOn: String
    }

    private struct Key: Hashable {
        let make: String
        let model: String
    }

    private var names: [Key: [String: String]] = [:]
    private var sonyMakes: Set<String> = []
    private var knownMakes: Set<String> = []

    public static let bundled: CameraNames = {
        // Resolve at the installed executable, without depending on build-machine resource paths.
        guard let executable = Bundle.main.executableURL,
              let bundle = Bundle(url: executable.deletingLastPathComponent()
                .appendingPathComponent("ExifmarkRenderer_ExifmarkCore.bundle")),
              let url = bundle.url(forResource: "CameraNames", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? CameraNames(data: data) else {
            return CameraNames()
        }
        return catalog
    }()

    private init() {}

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.version == 1 else { throw RenderError.invalid("相机名称映射版本无效。") }
        sonyMakes = Set((catalog.brands["sony"] ?? []).map(Self.normalize))
        knownMakes = Set(catalog.brands.values.flatMap { $0 }.map(Self.normalize))
        for entry in catalog.entries {
            guard let makes = catalog.brands[entry.brand], !makes.isEmpty, !entry.models.isEmpty,
                  let fallback = entry.names["default"], !Self.normalize(fallback).isEmpty,
                  entry.names.values.allSatisfy({ !Self.normalize($0).isEmpty }),
                  !entry.sources.isEmpty, entry.sources.allSatisfy({ $0.scheme == "https" && $0.host != nil }),
                  !entry.verifiedOn.isEmpty else {
                throw RenderError.invalid("相机名称映射条目不完整。")
            }
            for make in makes {
                for model in entry.models {
                    let key = Key(make: Self.normalize(make), model: Self.normalize(model))
                    guard !key.make.isEmpty, !key.model.isEmpty, names[key] == nil else {
                        throw RenderError.invalid("相机名称映射包含空值或重复的品牌型号。")
                    }
                    names[key] = entry.names
                }
            }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func singleLine(_ value: String) -> String {
        value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compose the watermark label while keeping model resolution and retained EXIF fields separate.
    public func watermarkName(make: String, model: String, style: CameraNameStyle = .common,
                              customName: String = "", language: String = "zh-CN") -> String {
        let camera = displayName(make: make, model: model, style: style, customName: customName, language: language)
        // Custom labels and EXIF model text are displayed without an added manufacturer.
        if !Self.singleLine(customName).isEmpty || style == .exif { return camera }
        let text = Self.singleLine(camera)
        guard !text.isEmpty else { return camera }
        let manufacturer = Self.singleLine(make)
        let brand = CameraBrand.resolve(make: make, model: model)
        let knownMake = knownMakes.contains(Self.normalize(make)) || CameraBrand.allCases.contains {
            Self.normalize(make) == $0.rawValue || Self.normalize(make) == Self.normalize($0.displayName)
        }
        // Keep an unrecognized manufacturer's text intact instead of inferring from a word within it.
        let prefix = (knownMake || manufacturer.isEmpty) ? (brand?.displayName ?? manufacturer) : manufacturer
        guard !prefix.isEmpty else { return camera }
        let normalized = Self.normalize(text)
        let normalizedPrefix = Self.normalize(prefix)
        if normalized == normalizedPrefix || normalized.hasPrefix(normalizedPrefix + " ") { return camera }
        return prefix + " " + text
    }

    /// The centered watermark already identifies the manufacturer with its logo.
    public func compactWatermarkName(make: String, model: String, style: CameraNameStyle = .common,
                                     customName: String = "") -> String {
        let camera = displayName(make: make, model: model, style: style, customName: customName)
        guard Self.singleLine(customName).isEmpty,
              let brand = CameraBrand.resolve(make: make, model: model) else { return camera }
        let words = camera.split(whereSeparator: { $0.isWhitespace })
        // Match whole leading words so model names containing a brand substring remain intact.
        let prefixes = [make, brand.displayName, brand.rawValue].sorted { $0.count > $1.count }
        for prefix in prefixes {
            let tokens = prefix.split(whereSeparator: { $0.isWhitespace })
            guard !tokens.isEmpty, words.count >= tokens.count,
                  zip(words.prefix(tokens.count), tokens).allSatisfy({ $0.lowercased() == $1.lowercased() }) else { continue }
            return words.dropFirst(tokens.count).joined(separator: " ")
        }
        return camera
    }

    public func displayName(make: String, model: String, style: CameraNameStyle = .common,
                            customName: String = "", language: String = "zh-CN") -> String {
        // Single-line display cleanup does not alter the retained EXIF fields.
        let custom = Self.singleLine(customName)
        if !custom.isEmpty { return custom }
        guard style == .common else { return model }
        let make = Self.normalize(make)
        if let localized = names[Key(make: make, model: Self.normalize(model))] {
            // Explicit regional names can override a family rule when needed.
            return localized[language] ?? localized["default"] ?? model
        }
        if sonyMakes.contains(make), let product = SonyCameraNames.displayName(model: model) { return product }
        return model
    }
}
