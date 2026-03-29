import Foundation

private enum SymbolNameFormatter {
    private static let lock = NSLock()
    private static var swiftCache: [String: String] = [:]
    private static var cppCache: [String: String] = [:]
    private static let swiftDemanglePath = resolveSwiftDemanglePath()
    private static let cppFiltPaths = ["/usr/bin/c++filt", "/opt/homebrew/bin/c++filt", "/usr/local/bin/c++filt"]

    static func displayName(for rawName: String) -> String {
        if rawName.hasPrefix("_$s") || rawName.hasPrefix("$s") {
            return demangleSwift(rawName) ?? rawName
        }
        if rawName.hasPrefix("__Z") || rawName.hasPrefix("_Z") {
            return demangleCPP(rawName) ?? rawName
        }
        return rawName.hasPrefix("_") ? String(rawName.dropFirst()) : rawName
    }

    private static func demangleSwift(_ mangled: String) -> String? {
        withCachedValue(for: mangled, cache: &swiftCache) {
            guard let swiftDemanglePath else {
                return nil
            }
            return runTool(path: swiftDemanglePath, arguments: ["-compact", mangled])
        }
    }

    private static func demangleCPP(_ mangled: String) -> String? {
        withCachedValue(for: mangled, cache: &cppCache) {
            for path in cppFiltPaths where FileManager.default.isExecutableFile(atPath: path) {
                if let result = runTool(path: path, arguments: [mangled]) {
                    return result
                }
            }
            return nil
        }
    }

    private static func withCachedValue(
        for key: String,
        cache: inout [String: String],
        producer: () -> String?
    ) -> String? {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let value = producer(), !value.isEmpty, value != key else {
            return nil
        }

        lock.lock()
        cache[key] = value
        lock.unlock()
        return value
    }

    private static func resolveSwiftDemanglePath() -> String? {
        let candidates = [
            "/usr/bin/swift-demangle",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return runTool(path: "/usr/bin/xcrun", arguments: ["--find", "swift-demangle"])
    }

    private static func runTool(path: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return result?.isEmpty == false ? result : nil
        } catch {
            return nil
        }
    }
}

/// Represents a symbol in the binary
struct Symbol: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: UInt64
    let size: UInt64
    let type: SymbolType
    let binding: SymbolBinding
    let section: String?

    var isImport: Bool {
        binding == .external && address == 0
    }

    var isExport: Bool {
        binding == .global && address != 0
    }

    var isLocal: Bool {
        binding == .local
    }

    var displayName: String {
        SymbolNameFormatter.displayName(for: name)
    }
}

/// Symbol type
enum SymbolType: String, Codable {
    case function = "Function"
    case data = "Data"
    case object = "Object"
    case section = "Section"
    case file = "File"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .function: return "f.square"
        case .data: return "d.square"
        case .object: return "cube"
        case .section: return "square.stack"
        case .file: return "doc"
        case .unknown: return "questionmark.square"
        }
    }
}

/// Symbol binding/visibility
enum SymbolBinding: String, Codable {
    case local = "Local"
    case global = "Global"
    case weak = "Weak"
    case external = "External"
    case undefined = "Undefined"
}
