import Foundation

public enum CameraBrand: String, CaseIterable {
    case sony, canon, nikon, fujifilm, leica, panasonic, lumix, pentax, ricoh
    case hasselblad, sigma, dji, kodak, phaseone, olympus

    public static func resolve(make: String, model: String) -> CameraBrand? {
        func words(_ value: String) -> [String] {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        func named(_ tokens: [String]) -> CameraBrand? {
            if tokens.starts(with: ["phase", "one"]) || tokens.contains("phaseone") { return .phaseone }
            return allCases.first { tokens.contains($0.rawValue) }
        }
        let manufacturer = words(make)
        let camera = words(model)
        // Ricoh manufactures both RICOH and PENTAX cameras.
        if manufacturer.contains("ricoh"), camera.first == "pentax" { return .pentax }
        if let brand = named(manufacturer) { return brand }
        // Model-only requests from earlier plugin versions remain supported.
        if let first = camera.first {
            if first == "phase", camera.dropFirst().first == "one" { return .phaseone }
            if let brand = CameraBrand(rawValue: first) { return brand }
            if manufacturer.isEmpty, ["ilce", "ilca", "dsc", "nex", "slt", "dslr"].contains(first) {
                return .sony
            }
        }
        return nil
    }
}
