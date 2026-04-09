import Foundation

// MARK: - European Number Formatting
// Thousands separator: "."   Decimal separator: ","
// e.g.  1 234,56 → "1.234,56"

private let _euFormatters: [Int: NumberFormatter] = {
    Dictionary(uniqueKeysWithValues: (0...4).map { d -> (Int, NumberFormatter) in
        let f = NumberFormatter()
        f.numberStyle          = .decimal
        f.groupingSeparator    = "."
        f.decimalSeparator     = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        return (d, f)
    })
}()

/// Formats a number with European separators (. thousands, , decimal).
/// euDecimal(1234.5, decimals: 2)  →  "1.234,50"
func euDecimal(_ value: Double, decimals: Int = 2) -> String {
    let d = min(max(decimals, 0), 4)
    return _euFormatters[d]?.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// Euro currency, 2 decimal places by default.
/// euEuro(98.39)  →  "€98,39"
func euEuro(_ value: Double, decimals: Int = 2) -> String {
    "€" + euDecimal(value, decimals: decimals)
}

/// Integer grams with dot thousands separator.
/// euGrams(4588)  →  "4.588g"
func euGrams(_ value: Double) -> String {
    euDecimal(value, decimals: 0) + "g"
}

/// Megabytes with 1 decimal place.
/// euMB(12.5)  →  "12,5 MB"
func euMB(_ value: Double) -> String {
    euDecimal(value, decimals: 1) + " MB"
}
