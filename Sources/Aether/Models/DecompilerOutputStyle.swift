import Foundation

enum DecompilerOutputStyle: String, CaseIterable {
    case pseudo
    case cStyle = "c"

    static let userDefaultsKey = "decompilerOutputStyle"

    var displayName: String {
        switch self {
        case .pseudo:
            return "Pseudo"
        case .cStyle:
            return "C-style"
        }
    }
}
