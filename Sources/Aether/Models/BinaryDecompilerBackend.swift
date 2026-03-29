import Foundation

enum BinaryDecompilerBackend: String, CaseIterable, Identifiable {
    case native = "native"
    case radare2 = "radare2"

    static let userDefaultsKey = "binaryDecompilerBackend"

    var id: String { rawValue }
}
