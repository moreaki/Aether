import Foundation

enum AetherCLI {
    private static let supportedCommands: Set<String> = ["help", "functions", "disassemble", "decompile"]

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
            let parsed = try CLIArguments(arguments: arguments)
            switch parsed.command {
            case .help:
                printHelp()
                return 0
            case .functions:
                try listFunctions(at: parsed.inputPath)
                return 0
            case .disassemble:
                try disassemble(at: parsed.inputPath, functionIdentifier: parsed.functionIdentifier, limit: parsed.limit)
                return 0
            case .decompile:
                try decompile(at: parsed.inputPath, functionIdentifier: parsed.functionIdentifier, backend: parsed.backend)
                return 0
            }
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
          Aether functions <input>
          Aether disassemble <input> [--function <name|address>] [--limit <count>]
          Aether decompile <input> [--function <name|address>] [--backend <native|radare2|internal|vineflower>]

        Notes:
          - Native binaries default to the entry function when `--function` is omitted.
          - JAR/class inputs default to the first discovered method when `--function` is omitted.
          - Addresses may be written as `0x4f2`, `4f2`, `proc_04F2`, or `sub_401000`.
        """)
    }

    private static func listFunctions(at inputPath: String) throws {
        let context = try CLIContext(inputPath: inputPath)
        let functions = try context.functions()

        for function in functions {
            print(String(format: "0x%llX\t%@", function.startAddress, function.displayName))
        }
    }

    private static func disassemble(at inputPath: String, functionIdentifier: String?, limit: Int?) throws {
        let context = try CLIContext(inputPath: inputPath)
        let function = try context.resolveFunction(identifier: functionIdentifier)
        let instructions = try context.disassemble(function: function)
        let visible = limit.map { Array(instructions.prefix($0)) } ?? instructions

        for instruction in visible {
            let operands = instruction.operands.isEmpty ? "" : " " + instruction.operands
            print(String(format: "0x%04llX  %@%@", instruction.address, instruction.mnemonic, operands))
        }
    }

    private static func decompile(at inputPath: String, functionIdentifier: String?, backend: String?) throws {
        let context = try CLIContext(inputPath: inputPath)
        let function = try context.resolveFunction(identifier: functionIdentifier)
        let output = try context.decompile(function: function, backend: backend)
        print(output)
    }
}

private enum CLICommand {
    case help
    case functions
    case disassemble
    case decompile
}

private struct CLIArguments {
    let command: CLICommand
    let inputPath: String
    let functionIdentifier: String?
    let limit: Int?
    let backend: String?

    init(arguments: [String]) throws {
        let commandToken = arguments.count > 1 ? arguments[1] : "help"
        switch commandToken {
        case "help", "--help", "-h":
            self.command = .help
            self.inputPath = ""
            self.functionIdentifier = nil
            self.limit = nil
            self.backend = nil
            return
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
            default:
                throw CLIError.usage("Unknown option: \(arguments[index])")
            }
            index += 1
        }

        self.functionIdentifier = functionIdentifier
        self.limit = limit
        self.backend = backend
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case functionNotFound(String)
    case unsupportedBackend(String)
    case javaMethodNotFound(String)

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
        }
    }
}

private final class CLIContext {
    private let url: URL
    private let binary: BinaryFile
    private let loader = BinaryLoader()
    private let disassembler = DisassemblerEngine()
    private let functionAnalyzer = FunctionAnalyzer()
    private let nativeDecompiler = Decompiler()
    private let javaDecompiler = JavaDecompiler()
    private var analyzedFunctionsCache: [Function]?

    init(inputPath: String) throws {
        self.url = URL(fileURLWithPath: inputPath)
        self.binary = try loader.load(from: url)
    }

    func functions() throws -> [Function] {
        if let javaFunctions = javaFunctions() {
            return javaFunctions
        }
        return try analyzedFunctions()
    }

    func resolveFunction(identifier: String?) throws -> Function {
        let functions = try functions()

        if let identifier {
            if let matched = functions.first(where: {
                $0.displayName == identifier || $0.shortDisplayName == identifier || $0.name == identifier
            }) {
                return matched
            }

            if let address = parseAddress(identifier),
               let matched = functions.first(where: { $0.startAddress == address }) {
                return matched
            }

            if let address = parseAutogeneratedAddress(identifier),
               let matched = functions.first(where: { $0.startAddress == address }) {
                return matched
            }

            if let javaClasses = binary.javaClasses, !javaClasses.isEmpty,
               let matched = try resolveJavaFunction(identifier: identifier, javaClasses: javaClasses) {
                return matched
            }

            throw CLIError.functionNotFound(identifier)
        }

        if let entry = functions.first(where: { $0.startAddress == binary.entryPoint }) {
            return entry
        }

        guard let first = functions.first else {
            throw CLIError.functionNotFound("default entry")
        }
        return first
    }

    func disassemble(function: Function) throws -> [Instruction] {
        guard let section = binary.sections.first(where: { $0.contains(address: function.startAddress) }) else {
            return []
        }

        let offset = Int(function.startAddress - section.address)
        let size = max(Int(function.size), 1)
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
                    address: function.startAddress,
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

    func decompile(function: Function, backend: String?) throws -> String {
        if let javaClasses = binary.javaClasses, !javaClasses.isEmpty {
            return try decompileJava(function: function, javaClasses: javaClasses, backend: backend)
        }

        let selectedBackend = backend?.lowercased() ?? "native"
        switch selectedBackend {
        case "native":
            let instructions = try disassemble(function: function)
            return nativeDecompiler.decompile(function: function, instructions: instructions, binary: binary)
        case "radare2":
            return try waitForAsyncResult { [self] in
                try Radare2Decompiler().decompile(function: function, binary: self.binary)
            }
        default:
            throw CLIError.unsupportedBackend(selectedBackend)
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

    private func decompileJava(function: Function, javaClasses: [JARLoader.JavaClass], backend: String?) throws -> String {
        let selectedBackend = backend?.lowercased() ?? "internal"

        switch selectedBackend {
        case "internal":
            for javaClass in javaClasses {
                let className = javaClass.thisClass.replacingOccurrences(of: "/", with: ".")
                for method in javaClass.methods {
                    let methodFullName = "\(className).\(method.name)\(method.descriptor)"
                    if methodFullName == function.name {
                        let decompiled = javaDecompiler.decompileMethod(method, in: javaClass)
                        return "\(decompiled.signature) {\n\(decompiled.body)\n}"
                    }
                }
            }
            throw CLIError.javaMethodNotFound(function.name)
        case "vineflower":
            let source = try VineflowerDecompiler().decompile(
                inputURL: url,
                preferredClassName: extractJavaClassName(from: function.name)
            )
            return source
        default:
            throw CLIError.unsupportedBackend(selectedBackend)
        }
    }

    private func analyzedFunctions() throws -> [Function] {
        if let analyzedFunctionsCache {
            return analyzedFunctionsCache
        }

        let analyzed = try waitForAsyncResult { [self] in
            await self.functionAnalyzer.analyze(binary: self.binary, disassembler: self.disassembler)
        }
        analyzedFunctionsCache = analyzed
        return analyzed
    }

    private func resolveJavaFunction(identifier: String, javaClasses: [JARLoader.JavaClass]) throws -> Function? {
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
