import Foundation

enum DecompilerLineNumberingMode: String, CaseIterable, Identifiable {
    case allOutput = "all_output"
    case functionOnly = "function_only"

    static let userDefaultsKey = "decompilerLineNumberingMode"

    var id: String { rawValue }
}
