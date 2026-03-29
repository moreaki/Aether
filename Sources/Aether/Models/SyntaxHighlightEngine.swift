import Foundation

enum SyntaxHighlightEngine: String, CaseIterable, Identifiable {
    case internalEngine = "internal"
    case highlightSwift = "highlightswift"

    static let userDefaultsKey = "syntaxHighlightEngine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .internalEngine:
            return "Internal"
        case .highlightSwift:
            return "HighlightSwift"
        }
    }
}
