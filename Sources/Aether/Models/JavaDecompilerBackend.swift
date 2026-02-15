import Foundation

enum JavaDecompilerBackend: String, CaseIterable, Identifiable {
    case internalEngine = "internal"
    case vineflower = "vineflower"

    static let userDefaultsKey = "javaDecompilerBackend"

    var id: String { rawValue }
}
