import Foundation

enum AetherCLI {
    private static let supportedCommands: Set<String> = ["help", "analyze", "functions", "disassemble", "decompile"]

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count > 1 else {
            return nil
        }

        let command = arguments[1]
        guard supportedCommands.contains(command) || command == "--help" || command == "-h" else {
            return nil
        }

        return run(arguments: arguments)
    }

    private static func run(arguments: [String]) -> Int32 {
        do {
            let invocation = try CLIInvocation(arguments: arguments)

            switch invocation.command {
            case .help:
                printHelp()
            case .analyze:
                try analyze(invocation)
            case .functions:
                try listFunctions(invocation)
            case .disassemble:
                try disassemble(invocation)
            case .decompile:
                try decompile(invocation)
            }
            return 0
        } catch {
            fputs("Aether CLI error: \(error.localizedDescription)\n", stderr)
            fputs("Run `Aether help` for usage.\n", stderr)
            return 1
        }
    }

    private static func printHelp() {
        print("""
        Aether CLI

        Usage:
          Aether help
          Aether analyze <input> [--refresh] [--output <plain|json>]
          Aether functions <input> [--refresh] [--no-cache] [--output <plain|json>]
          Aether disassemble <input> [--function <name|address>] [--limit <count>] [--refresh] [--no-cache] [--output <plain|ansi|json>]
          Aether decompile <input> [--function <name|address>] [--backend <native|radare2|internal|vineflower>] [--refresh] [--no-cache] [--output <plain|ansi|json>] [--line-numbers <none|all|function>] [--highlight]

        Defaults:
          - Native binaries default to `start` if present, otherwise the entry point.
          - JAR/class inputs default to the first discovered method.
          - `decompile` backend defaults to `native` for native binaries and `internal` for Java archives/classes.
          - `disassemble` and `decompile` output defaults to `plain`.
          - `decompile` line numbering defaults to `none`.
          - CLI commands use the persistent analysis cache by default; `--refresh` rebuilds it and `--no-cache` bypasses it.

        Notes:
          - `analyze` performs full function analysis and stores a cache snapshot for later commands.
          - `decompile` still decompiles the selected function on demand.
          - Addresses may be written as `0x4f2`, `4f2`, `proc_04F2`, or `sub_401000`.
          - `--highlight` is a shortcut for `--output ansi`.
        """)
    }

    private static func analyze(_ invocation: CLIInvocation) throws {
        let context = try CLIContext(
            inputPath: invocation.inputPath,
            useCache: invocation.useCache,
            refreshCache: invocation.refreshCache
        )
        let functions = try context.analyzeAndCache()

        switch invocation.outputFormat {
        case .plain, .ansi:
            let summary = try context.analysisSummary(functionCount: functions.count)
            print("Analyzed \(summary.inputName)")
            print("Format: \(summary.format)")
            print("Architecture: \(summary.architecture)")
            print("Functions: \(summary.functionCount)")
            if let cachePath = summary.cachePath {
                print("Cache: \(cachePath)")
            }
        case .json:
            let payload = try context.analysisSummary(functionCount: functions.count)
            print(try encodeJSON(payload))
        }
    }

    private static func listFunctions(_ invocation: CLIInvocation) throws {
        let context = try CLIContext(
            inputPath: invocation.inputPath,
            useCache: invocation.useCache,
            refreshCache: invocation.refreshCache
        )
        let functions = try context.functions()

        switch invocation.outputFormat {
        case .plain, .ansi:
            for function in functions {
                print(String(format: "0x%llX\t%@", function.startAddress, function.displayName))
            }
        case .json:
            let payload = functions.map { FunctionSummary(function: $0) }
            print(try encodeJSON(payload))
        }
    }

    private static func disassemble(_ invocation: CLIInvocation) throws {
        let context = try CLIContext(
            inputPath: invocation.inputPath,
            useCache: invocation.useCache,
            refreshCache: invocation.refreshCache
        )
        let function = try context.resolveFunction(identifier: invocation.functionIdentifier)
        let instructions = try context.disassemble(function: function)
        let visible = invocation.limit.map { Array(instructions.prefix($0)) } ?? instructions

        switch invocation.outputFormat {
        case .plain:
            for instruction in visible {
                print(renderDisassemblyLine(instruction))
            }
        case .ansi:
            for instruction in visible {
                print(renderANSIAssemblyLine(instruction))
            }
        case .json:
            let payload = visible.map(InstructionSummary.init)
            print(try encodeJSON(payload))
        }
    }

    private static func decompile(_ invocation: CLIInvocation) throws {
        let context = try CLIContext(
            inputPath: invocation.inputPath,
            useCache: invocation.useCache,
            refreshCache: invocation.refreshCache
        )
        let function = try context.resolveFunction(identifier: invocation.functionIdentifier)
        let result = try context.decompile(function: function, backend: invocation.backend)

        switch invocation.outputFormat {
        case .plain:
            print(applyLineNumbering(to: result.source, mode: invocation.lineNumbers, ansi: false))
        case .ansi:
            let numbered = applyLineNumbering(to: result.source, mode: invocation.lineNumbers, ansi: false)
            print(highlightCodeANSI(numbered, language: result.language))
        case .json:
            let payload = DecompiledOutputSummary(
                backend: result.backend,
                language: result.language,
                function: FunctionSummary(function: result.function),
                source: applyLineNumbering(to: result.source, mode: invocation.lineNumbers, ansi: false)
            )
            print(try encodeJSON(payload))
        }
    }
}

private enum CLICommand {
    case help
    case analyze
    case functions
    case disassemble
    case decompile
}

private enum CLIOutputFormat: String {
    case plain
    case ansi
    case json
}

private enum CLILineNumbers: String {
    case none
    case all
    case function
}

private struct CLIInvocation {
    let command: CLICommand
    let inputPath: String
    let functionIdentifier: String?
    let limit: Int?
    let backend: String?
    let outputFormat: CLIOutputFormat
    let lineNumbers: CLILineNumbers
    let useCache: Bool
    let refreshCache: Bool

    init(arguments: [String]) throws {
        let commandToken = arguments.count > 1 ? arguments[1] : "help"
        switch commandToken {
        case "help", "--help", "-h":
            self.command = .help
            self.inputPath = ""
            self.functionIdentifier = nil
            self.limit = nil
            self.backend = nil
            self.outputFormat = .plain
            self.lineNumbers = .none
            self.useCache = true
            self.refreshCache = false
            return
        case "analyze":
            self.command = .analyze
        case "functions":
            self.command = .functions
        case "disassemble":
            self.command = .disassemble
        case "decompile":
            self.command = .decompile
        default:
            throw CLIError.usage("Unknown command: \(commandToken)")
        }

        guard arguments.count > 2 else {
            throw CLIError.usage("Missing input path")
        }

        self.inputPath = arguments[2]

        var functionIdentifier: String?
        var limit: Int?
        var backend: String?
        var outputFormat: CLIOutputFormat = .plain
        var lineNumbers: CLILineNumbers = .none
        var useCache = true
        var refreshCache = false
        var index = 3

        while index < arguments.count {
            switch arguments[index] {
            case "--function":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("Missing value for --function")
                }
                functionIdentifier = arguments[index]
            case "--limit":
                index += 1
                guard index < arguments.count, let parsedLimit = Int(arguments[index]) else {
                    throw CLIError.usage("Missing or invalid value for --limit")
                }
                limit = parsedLimit
            case "--backend":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("Missing value for --backend")
                }
                backend = arguments[index]
            case "--output":
                index += 1
                guard index < arguments.count, let parsedOutput = CLIOutputFormat(rawValue: arguments[index].lowercased()) else {
                    throw CLIError.usage("Missing or invalid value for --output")
                }
                outputFormat = parsedOutput
            case "--line-numbers":
                index += 1
                guard index < arguments.count, let parsedLineNumbers = CLILineNumbers(rawValue: arguments[index].lowercased()) else {
                    throw CLIError.usage("Missing or invalid value for --line-numbers")
                }
                lineNumbers = parsedLineNumbers
            case "--highlight":
                outputFormat = .ansi
            case "--refresh":
                refreshCache = true
            case "--no-cache":
                useCache = false
            default:
                throw CLIError.usage("Unknown option: \(arguments[index])")
            }
            index += 1
        }

        self.functionIdentifier = functionIdentifier
        self.limit = limit
        self.backend = backend
        self.outputFormat = outputFormat
        self.lineNumbers = lineNumbers
        self.useCache = useCache
        self.refreshCache = refreshCache
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case functionNotFound(String)
    case unsupportedBackend(String)
    case javaMethodNotFound(String)
    case cacheError(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .functionNotFound(let identifier):
            return "Could not resolve function `\(identifier)`."
        case .unsupportedBackend(let backend):
            return "Unsupported backend `\(backend)` for this input."
        case .javaMethodNotFound(let identifier):
            return "Could not find Java method `\(identifier)`."
        case .cacheError(let message):
            return message
        }
    }
}

private final class CLIContext {
    private let url: URL
    private let binary: BinaryFile
    private let disassembler = DisassemblerEngine()
    private let functionAnalyzer = FunctionAnalyzer()
    private let nativeDecompiler = Decompiler()
    private let javaDecompiler = JavaDecompiler()
    private let useCache: Bool
    private let refreshCache: Bool
    private let cacheManager: CLIAnalysisCacheManager
    private var analyzedFunctionsCache: [Function]?
    private var analyzedSingleFunctionsByAddress: [UInt64: Function] = [:]

    init(inputPath: String, useCache: Bool, refreshCache: Bool) throws {
        self.url = URL(fileURLWithPath: inputPath)
        self.binary = try BinaryLoader().load(from: url)
        self.useCache = useCache
        self.refreshCache = refreshCache
        self.cacheManager = try CLIAnalysisCacheManager(url: url, binary: binary)

        if useCache && !refreshCache, let cached = try cacheManager.load() {
            self.analyzedFunctionsCache = cached
        }
    }

    func analyzeAndCache() throws -> [Function] {
        let functions: [Function]
        if let javaFunctions = javaFunctions() {
            functions = javaFunctions
            analyzedFunctionsCache = javaFunctions
        } else {
            functions = try analyzedFunctions(forceRefresh: true)
        }
        if useCache {
            try cacheManager.save(functions: functions)
        }
        return functions
    }

    func analysisSummary(functionCount: Int) throws -> AnalysisSummary {
        AnalysisSummary(
            inputName: url.lastPathComponent,
            format: binary.format.rawValue,
            architecture: binary.architecture.rawValue,
            functionCount: functionCount,
            cachePath: useCache ? try cacheManager.cacheURL().path : nil
        )
    }

    func functions() throws -> [Function] {
        if let javaFunctions = javaFunctions() {
            return javaFunctions
        }
        return try analyzedFunctions(forceRefresh: refreshCache)
    }

    func resolveFunction(identifier: String?) throws -> Function {
        if let identifier {
            if let address = parseAddress(identifier),
               let matched = try analyzedFunction(at: address, preferredName: identifier) {
                return matched
            }

            if let address = parseAutogeneratedAddress(identifier),
               let matched = try analyzedFunction(at: address, preferredName: identifier) {
                return matched
            }

            if identifier == "start" || identifier == "_start",
               let start = try defaultNativeFunction(preferredIdentifier: identifier) {
                return start
            }

            if let symbol = binary.symbols.first(where: {
                $0.type == .function && ($0.displayName == identifier || $0.name == identifier)
            }),
               let matched = try analyzedFunction(at: symbol.address, preferredName: symbol.displayName) {
                return matched
            }

            if let javaClasses = binary.javaClasses, !javaClasses.isEmpty,
               let matched = resolveJavaFunction(identifier: identifier, javaClasses: javaClasses) {
                return matched
            }

            let functions = try functions()
            if let matched = functions.first(where: {
                $0.displayName == identifier || $0.shortDisplayName == identifier || $0.name == identifier
            }) {
                return matched
            }

            throw CLIError.functionNotFound(identifier)
        }

        if let javaClasses = binary.javaClasses, !javaClasses.isEmpty {
            let functions = javaFunctions() ?? []
            if let start = functions.first(where: { $0.displayName == "start" || $0.name == "start" }) {
                return start
            }
            guard let first = functions.first else {
                throw CLIError.functionNotFound("default entry")
            }
            return first
        }

        if let nativeDefault = try defaultNativeFunction(preferredIdentifier: nil) {
            return nativeDefault
        }

        let functions = try functions()
        if let start = functions.first(where: { $0.displayName == "start" || $0.name == "start" }) {
            return start
        }
        guard let first = functions.first else {
            throw CLIError.functionNotFound("default entry")
        }
        return first
    }

    func disassemble(function: Function) throws -> [Instruction] {
        let preparedFunction = try analyzedFunction(at: function.startAddress, preferredName: function.name) ?? function
        guard let section = binary.sections.first(where: { $0.contains(address: preparedFunction.startAddress) }) else {
            return []
        }

        let offset = Int(preparedFunction.startAddress - section.address)
        let size = max(Int(preparedFunction.size), 1)
        guard offset >= 0, offset < section.data.count else {
            return []
        }

        let hardEnd = min(section.data.count, offset + size + (binary.format == .dos || binary.architecture == .x86_16 ? 64 : 0))
        var endOffset = min(offset + size, section.data.count)
        var instructions: [Instruction] = []

        repeat {
            instructions = try waitForAsyncResult { [self] in
                await self.disassembler.disassemble(
                    data: Data(section.data[offset..<endOffset]),
                    address: preparedFunction.startAddress,
                    architecture: self.binary.architecture
                )
            }

            if !needsTailExtension(instructions.last) || endOffset >= hardEnd {
                break
            }

            endOffset = min(endOffset + 16, hardEnd)
        } while true

        return instructions
    }

    func decompile(function: Function, backend: String?) throws -> DecompiledOutput {
        if let javaClasses = binary.javaClasses, !javaClasses.isEmpty {
            return try decompileJava(function: function, javaClasses: javaClasses, backend: backend)
        }

        let selectedBackend: BinaryDecompilerBackend
        if let backend {
            guard let parsed = BinaryDecompilerBackend(rawValue: backend.lowercased()) else {
                throw CLIError.unsupportedBackend(backend)
            }
            selectedBackend = parsed
        } else {
            selectedBackend = .native
        }
        switch selectedBackend {
        case .native:
            let preparedFunction = try analyzedFunction(at: function.startAddress, preferredName: function.name) ?? function
            let instructions = try disassemble(function: preparedFunction)
            let source = nativeDecompiler.decompile(function: preparedFunction, instructions: instructions, binary: binary)
            return DecompiledOutput(
                backend: selectedBackend.rawValue,
                language: binary.javaClasses == nil ? "c" : "java",
                function: preparedFunction,
                source: source
            )
        case .radare2:
            let source = try waitForAsyncResult { [self] in
                try Radare2Decompiler().decompile(function: function, binary: self.binary)
            }
            return DecompiledOutput(
                backend: selectedBackend.rawValue,
                language: "c",
                function: function,
                source: source
            )
        }
    }

    private func javaFunctions() -> [Function]? {
        guard binary.javaClasses != nil else {
            return nil
        }

        return binary.symbols
            .filter { $0.type == .function && $0.address != 0 }
            .map { Function(name: $0.name, startAddress: $0.address, endAddress: $0.address + max($0.size, 1)) }
            .sorted { $0.startAddress < $1.startAddress }
    }

    private func decompileJava(function: Function, javaClasses: [JARLoader.JavaClass], backend: String?) throws -> DecompiledOutput {
        let selectedBackend: JavaDecompilerBackend
        if let backend {
            guard let parsed = JavaDecompilerBackend(rawValue: backend.lowercased()) else {
                throw CLIError.unsupportedBackend(backend)
            }
            selectedBackend = parsed
        } else {
            selectedBackend = .internalEngine
        }

        switch selectedBackend {
        case .internalEngine:
            for javaClass in javaClasses {
                let className = javaClass.thisClass.replacingOccurrences(of: "/", with: ".")
                for method in javaClass.methods {
                    let methodFullName = "\(className).\(method.name)\(method.descriptor)"
                    if methodFullName == function.name {
                        let decompiled = javaDecompiler.decompileMethod(method, in: javaClass)
                        let source = "\(decompiled.signature) {\n\(decompiled.body)\n}"
                        return DecompiledOutput(
                            backend: selectedBackend.rawValue,
                            language: "java",
                            function: function,
                            source: source
                        )
                    }
                }
            }
            throw CLIError.javaMethodNotFound(function.name)
        case .vineflower:
            let source = try VineflowerDecompiler().decompile(
                inputURL: url,
                preferredClassName: extractJavaClassName(from: function.name)
            )
            return DecompiledOutput(
                backend: selectedBackend.rawValue,
                language: "java",
                function: function,
                source: source
            )
        }
    }

    private func analyzedFunctions(forceRefresh: Bool) throws -> [Function] {
        if let analyzedFunctionsCache, !forceRefresh {
            return analyzedFunctionsCache
        }

        let analyzed = try waitForAsyncResult { [self] in
            await self.functionAnalyzer.analyze(binary: self.binary, disassembler: self.disassembler)
        }
        analyzedFunctionsCache = analyzed
        if useCache {
            try cacheManager.save(functions: analyzed)
        }
        return analyzed
    }

    private func analyzedFunction(at address: UInt64, preferredName: String? = nil) throws -> Function? {
        if let cached = analyzedSingleFunctionsByAddress[address], !cached.basicBlocks.isEmpty {
            return cached
        }

        if let fullCache = analyzedFunctionsCache?.first(where: { $0.startAddress == address }),
           !fullCache.basicBlocks.isEmpty {
            analyzedSingleFunctionsByAddress[address] = fullCache
            return fullCache
        }

        guard binary.sections.contains(where: { $0.contains(address: address) }) else {
            return nil
        }

        let analyzed = try waitForAsyncResult { [self] in
            await self.functionAnalyzer.analyzeSingleFunction(
                binary: self.binary,
                disassembler: self.disassembler,
                address: address,
                preferredName: preferredName
            )
        }

        if let analyzed {
            analyzedSingleFunctionsByAddress[address] = analyzed
        }
        return analyzed
    }

    private func defaultNativeFunction(preferredIdentifier: String?) throws -> Function? {
        if let startSymbol = binary.symbols.first(where: {
            $0.type == .function && ($0.displayName == "start" || $0.name == "start")
        }) {
            return try analyzedFunction(at: startSymbol.address, preferredName: preferredIdentifier ?? startSymbol.displayName)
        }

        if binary.entryPoint != 0 {
            return try analyzedFunction(at: binary.entryPoint, preferredName: preferredIdentifier ?? "start")
        }

        if let firstSymbol = binary.symbols.first(where: { $0.type == .function && $0.address != 0 }) {
            return try analyzedFunction(at: firstSymbol.address, preferredName: firstSymbol.displayName)
        }

        return nil
    }

    private func resolveJavaFunction(identifier: String, javaClasses: [JARLoader.JavaClass]) -> Function? {
        let availableFunctions = javaFunctions() ?? []
        if let matched = availableFunctions.first(where: { $0.name == identifier || $0.displayName == identifier }) {
            return matched
        }

        for javaClass in javaClasses {
            let className = javaClass.thisClass.replacingOccurrences(of: "/", with: ".")
            for method in javaClass.methods {
                let fullName = "\(className).\(method.name)\(method.descriptor)"
                let shortName = "\(className).\(method.name)"
                if identifier == fullName || identifier == shortName {
                    if let matched = availableFunctions.first(where: { $0.name == fullName }) {
                        return matched
                    }
                }
            }
        }

        return nil
    }

    private func extractJavaClassName(from functionName: String) -> String? {
        guard let descriptorStart = functionName.firstIndex(of: "(") else {
            return nil
        }

        let beforeDescriptor = functionName[..<descriptorStart]
        guard let lastDot = beforeDescriptor.lastIndex(of: ".") else {
            return nil
        }

        return String(beforeDescriptor[..<lastDot])
    }

    private func parseAddress(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        return UInt64(trimmed, radix: 16) ?? UInt64(trimmed)
    }

    private func parseAutogeneratedAddress(_ value: String) -> UInt64? {
        for prefix in ["proc_", "sub_", "loc_", "fcn."] where value.lowercased().hasPrefix(prefix) {
            return UInt64(value.dropFirst(prefix.count), radix: 16)
        }
        return nil
    }

    private func needsTailExtension(_ instruction: Instruction?) -> Bool {
        guard let instruction,
              instruction.mnemonic.lowercased() == "db",
              let opcode = instruction.bytes.first else {
            return false
        }

        switch opcode {
        case 0x9A, 0xE8, 0xE9, 0xEA, 0xEB, 0xFF:
            return binary.format == .dos || binary.architecture == .x86_16
        default:
            return false
        }
    }
}

private struct CLIAnalysisCacheManager {
    private let url: URL
    private let binary: BinaryFile
    private let fileSize: UInt64
    private let modificationTime: TimeInterval

    init(url: URL, binary: BinaryFile) throws {
        self.url = url.standardizedFileURL
        self.binary = binary

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? UInt64(binary.fileSize)
        self.modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    func load() throws -> [Function]? {
        let cacheURL = try cacheURL()
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: cacheURL)
        let snapshot = try JSONDecoder().decode(CLIAnalysisCacheSnapshot.self, from: data)

        guard snapshot.version == CLIAnalysisCacheSnapshot.currentVersion,
              snapshot.inputPath == url.path,
              snapshot.fileSize == fileSize,
              snapshot.modificationTime == modificationTime else {
            return nil
        }

        return snapshot.functions.map(\.function)
    }

    func save(functions: [Function]) throws {
        let cacheURL = try cacheURL()
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let snapshot = CLIAnalysisCacheSnapshot(
            inputPath: url.path,
            fileSize: fileSize,
            modificationTime: modificationTime,
            format: binary.format.rawValue,
            architecture: binary.architecture.rawValue,
            functions: functions.map(CachedFunction.init(function:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: cacheURL, options: .atomic)
    }

    func cacheURL() throws -> URL {
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Aether/cli", isDirectory: true)
        let key = stableHash("\(url.path)|\(fileSize)|\(modificationTime)")
        return cacheRoot.appendingPathComponent("\(key).json")
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private struct CLIAnalysisCacheSnapshot: Codable {
    static let currentVersion = 2

    let version: Int
    let inputPath: String
    let fileSize: UInt64
    let modificationTime: TimeInterval
    let format: String
    let architecture: String
    let functions: [CachedFunction]

    init(
        inputPath: String,
        fileSize: UInt64,
        modificationTime: TimeInterval,
        format: String,
        architecture: String,
        functions: [CachedFunction]
    ) {
        self.version = Self.currentVersion
        self.inputPath = inputPath
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.format = format
        self.architecture = architecture
        self.functions = functions
    }
}

private struct CachedFunction: Codable {
    let name: String
    let startAddress: UInt64
    let endAddress: UInt64
    let isLeaf: Bool

    init(function: Function) {
        self.name = function.name
        self.startAddress = function.startAddress
        self.endAddress = function.endAddress
        self.isLeaf = function.isLeaf
    }

    var function: Function {
        var function = Function(name: name, startAddress: startAddress, endAddress: endAddress)
        function.isLeaf = isLeaf
        return function
    }
}

private struct AnalysisSummary: Codable {
    let inputName: String
    let format: String
    let architecture: String
    let functionCount: Int
    let cachePath: String?
}

private struct FunctionSummary: Codable {
    let name: String
    let displayName: String
    let startAddress: UInt64
    let endAddress: UInt64
    let size: UInt64

    init(function: Function) {
        self.name = function.name
        self.displayName = function.displayName
        self.startAddress = function.startAddress
        self.endAddress = function.endAddress
        self.size = function.size
    }
}

private struct InstructionSummary: Codable {
    let address: UInt64
    let size: Int
    let bytes: [UInt8]
    let mnemonic: String
    let operands: String
    let type: String
    let branchTarget: UInt64?

    init(_ instruction: Instruction) {
        self.address = instruction.address
        self.size = instruction.size
        self.bytes = instruction.bytes
        self.mnemonic = instruction.mnemonic
        self.operands = instruction.operands
        self.type = instruction.type.rawValue
        self.branchTarget = instruction.branchTarget
    }
}

private struct DecompiledOutput {
    let backend: String
    let language: String
    let function: Function
    let source: String
}

private struct DecompiledOutputSummary: Codable {
    let backend: String
    let language: String
    let function: FunctionSummary
    let source: String
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func renderDisassemblyLine(_ instruction: Instruction) -> String {
    let operands = instruction.operands.isEmpty ? "" : " " + instruction.operands
    return String(format: "0x%04llX  %@%@", instruction.address, instruction.mnemonic, operands)
}

private func renderANSIAssemblyLine(_ instruction: Instruction) -> String {
    let address = ansi(.dim, String(format: "0x%04llX", instruction.address))
    let mnemonic = ansi(.cyan, instruction.mnemonic)
    let operands = instruction.operands.isEmpty ? "" : " " + highlightAssemblyOperandsANSI(instruction.operands)
    return "\(address)  \(mnemonic)\(operands)"
}

private func highlightAssemblyOperandsANSI(_ operands: String) -> String {
    var rendered = operands
    let replacements: [(String, ANSIColor)] = [
        ("0x[0-9a-fA-F]+|\\b\\d+\\b", .magenta),
        ("\\b(ax|bx|cx|dx|si|di|bp|sp|al|ah|bl|bh|cl|ch|dl|dh|eax|ebx|ecx|edx|esi|edi|ebp|esp|rax|rbx|rcx|rdx|rsi|rdi|rbp|rsp|ds|es|cs|ss)\\b", .blue)
    ]

    for (pattern, color) in replacements {
        rendered = applyANSIRegex(pattern: pattern, to: rendered, color: color)
    }
    return rendered
}

private func applyLineNumbering(to source: String, mode: CLILineNumbers, ansi: Bool) -> String {
    guard mode != .none else {
        return source
    }

    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let firstContentIndex = lines.firstIndex { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.hasPrefix("//")
    } ?? 0

    let width: Int
    switch mode {
    case .all:
        width = String(max(lines.count, 1)).count
    case .function:
        width = String(max(lines.count - firstContentIndex, 1)).count
    case .none:
        width = 1
    }

    return lines.enumerated().map { index, line in
        let number: String
        switch mode {
        case .all:
            number = String(format: "%\(width)d", index + 1)
        case .function:
            if index < firstContentIndex {
                number = String(repeating: " ", count: width)
            } else {
                number = String(format: "%\(width)d", index - firstContentIndex + 1)
            }
        case .none:
            number = ""
        }

        if mode == .none {
            return line
        }

        let prefix = ansi ? selfAnsi(.dim, "\(number) | ") : "\(number) | "
        return prefix + line
    }.joined(separator: "\n")
}

private func highlightCodeANSI(_ source: String, language: String) -> String {
    let keywords: Set<String> = language == "java"
        ? ["if", "else", "while", "for", "return", "break", "continue", "switch", "case", "default", "public", "private", "protected", "static", "final", "new", "this", "super", "throw", "try", "catch", "finally", "true", "false", "null"]
        : ["if", "else", "while", "for", "return", "break", "continue", "switch", "case", "default", "void", "int", "char", "long", "short", "unsigned", "signed", "const", "static", "struct", "enum", "typedef", "goto"]

    let types: Set<String> = ["void", "int", "char", "long", "short", "unsigned", "signed", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "boolean", "byte", "float", "double", "String", "Object"]

    return source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        let text = String(line)
        if let commentRange = text.range(of: "//") {
            let codePart = String(text[..<commentRange.lowerBound])
            let commentPart = String(text[commentRange.lowerBound...])
            return highlightCodeTokensANSI(codePart, keywords: keywords, types: types) + ansi(.green, commentPart)
        }
        return highlightCodeTokensANSI(text, keywords: keywords, types: types)
    }.joined(separator: "\n")
}

private func highlightCodeTokensANSI(_ line: String, keywords: Set<String>, types: Set<String>) -> String {
    var remaining = line[...]
    var output = ""

    while !remaining.isEmpty {
        if remaining.first?.isWhitespace == true {
            output.append(remaining.removeFirst())
            continue
        }

        if remaining.first == "\"" {
            var literal = "\""
            remaining.removeFirst()
            while let next = remaining.first {
                literal.append(next)
                remaining.removeFirst()
                if next == "\"" && !literal.hasSuffix("\\\"") {
                    break
                }
            }
            output += ansi(.yellow, literal)
            continue
        }

        if remaining.hasPrefix("0x") || remaining.first?.isNumber == true {
            var number = ""
            if remaining.hasPrefix("0x") {
                number = "0x"
                remaining.removeFirst(2)
                while let next = remaining.first, next.isHexDigit {
                    number.append(next)
                    remaining.removeFirst()
                }
            } else {
                while let next = remaining.first, next.isNumber {
                    number.append(next)
                    remaining.removeFirst()
                }
            }
            output += ansi(.magenta, number)
            continue
        }

        if remaining.first?.isLetter == true || remaining.first == "_" {
            var identifier = ""
            while let next = remaining.first, next.isLetter || next.isNumber || next == "_" || next == "." {
                identifier.append(next)
                remaining.removeFirst()
            }

            if keywords.contains(identifier) {
                output += ansi(.cyan, identifier)
            } else if types.contains(identifier) {
                output += ansi(.blue, identifier)
            } else if identifier.hasPrefix("proc_") || identifier.hasPrefix("sub_") || identifier == "start" {
                output += ansi(.brightCyan, identifier)
            } else {
                output += identifier
            }
            continue
        }

        output.append(remaining.removeFirst())
    }

    return output
}

private func applyANSIRegex(pattern: String, to text: String, color: ANSIColor) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return text
    }

    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard !matches.isEmpty else {
        return text
    }

    var output = text
    for match in matches.reversed() {
        guard let range = Range(match.range, in: output) else { continue }
        let value = String(output[range])
        output.replaceSubrange(range, with: ansi(color, value))
    }
    return output
}

private enum ANSIColor: String {
    case dim = "\u{001B}[2m"
    case blue = "\u{001B}[34m"
    case cyan = "\u{001B}[36m"
    case brightCyan = "\u{001B}[96m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case magenta = "\u{001B}[35m"
}

private func ansi(_ color: ANSIColor, _ text: String) -> String {
    color.rawValue + text + "\u{001B}[0m"
}

private func selfAnsi(_ color: ANSIColor, _ text: String) -> String {
    ansi(color, text)
}

private func waitForAsyncResult<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!

    Task.detached(priority: .userInitiated) {
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    switch result! {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    }
}
