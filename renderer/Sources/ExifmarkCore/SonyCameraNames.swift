import Foundation

/// Sony family grammars; no per-camera product table is required.
/// Rules describe naming syntax and also apply to future model numbers using the same syntax.
enum SonyCameraNames {
    private static let alpha = try! NSRegularExpression(
        pattern: #"\AILCE-([1-9][0-9]*)(CR|R|S|C)?(?:M([2-9]|[1-9][0-9]{1,2})([A-Z]?))?\z"#)
    private static let zv = try! NSRegularExpression(
        pattern: #"\AZV-E([1-9][0-9]*)(?:M([2-9]|[1-9][0-9]{1,2})([A-Z]?))?\z"#)
    private static let nex = try! NSRegularExpression(pattern: #"\ANEX-[A-Z]?[1-9][0-9]*[A-Z]?\z"#)
    private static let qx = try! NSRegularExpression(pattern: #"\AILCE-QX[1-9][0-9]*\z"#)

    private static func captures(_ regex: NSRegularExpression, _ value: String) -> [String]? {
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: value).map { String(value[$0]) } ?? ""
        }
    }

    private static func roman(_ value: String) -> String {
        var number = Int(value) ?? 0
        var result = ""
        for (amount, symbol) in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
                                 (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
                                 (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
            while number >= amount {
                result += symbol
                number -= amount
            }
        }
        return result
    }

    static func displayName(model: String) -> String? {
        var model = model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Some catalogs include the manufacturer in Model as well as Make.
        if model.hasPrefix("SONY ") {
            model = String(model.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func name(_ base: String, generation: String, revision: String) -> String {
            let product = base + (generation.isEmpty ? "" : " " + roman(generation))
            // Revision letters remain attached to the generation, e.g. IV + A becomes IVA.
            return product + revision
        }
        if let parts = captures(alpha, model) {
            return name("α" + parts[1] + parts[2], generation: parts[3], revision: parts[4])
        }
        if let parts = captures(zv, model) {
            return name("ZV-E" + parts[1], generation: parts[2], revision: parts[3])
        }
        if captures(nex, model) != nil || captures(qx, model) != nil { return model }
        return nil
    }
}
