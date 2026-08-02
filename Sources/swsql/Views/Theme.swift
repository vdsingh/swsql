import SWSQLCore
import SwiftTUI

/// The palette, kept in one place so the panes stay visually consistent.
enum Theme {
    static let accent = Color.cyan
    static let dim = Color.brightBlack
    static let text = Color.default
    static let strong = Color.brightWhite

    static let success = Color.green
    static let failure = Color.red
    static let warning = Color.yellow

    static let headerBackground = Color.blue
    static let headerForeground = Color.brightWhite

    static let numeric = Color.brightCyan
    static let null = Color.brightBlack
    static let separator = Color.brightBlack

    static func color(for role: TextSpan.Role) -> Color {
        switch role {
        case .header: return accent
        case .rule: return separator
        case .separator: return separator
        case .gutter: return dim
        case .value: return text
        case .numeric: return numeric
        case .null: return null
        }
    }
}

extension Extended {
    /// `intValue` traps on an infinite dimension, which can reach a
    /// `GeometryReader` before the first real layout pass. This keeps a stray
    /// infinity from taking the whole app down.
    var finiteValue: Int? {
        let negativeInfinity = Extended(0) - .infinity
        guard self != .infinity, self != negativeInfinity else { return nil }
        return intValue
    }
}
