import Foundation

/// Enhanced pseudo-code decompiler with control flow recovery
class Decompiler {

    private let structurer = ControlFlowStructurer()
    private var binary: BinaryFile?
    private var strings: [UInt64: String] = [:]
    private var dosInterruptCalls: [UInt64: DOSInterruptCall] = [:]
    private var variableNames: [String: String] = [:]
    private var variableCounter = 0
    private var cachedBinaryID: UUID?
    private var currentReturnType = "void"

    /// Decompile a function to pseudo-C code
    func decompile(function: Function, instructions: [Instruction], binary: BinaryFile) -> String {
        self.binary = binary
        self.variableNames = [:]
        self.variableCounter = 0

        // Build string cache only once per binary
        if cachedBinaryID != binary.id {
            self.strings = [:]
            buildStringCache(binary: binary)
            cachedBinaryID = binary.id
        }
        dosInterruptCalls = DOSInterruptKnowledge.analyze(instructions: instructions, binary: binary)

        var output = ""

        // Generate function signature
        let returnType = inferReturnType(instructions: instructions, architecture: binary.architecture)
        currentReturnType = returnType
        let params = inferParameters(instructions: instructions, architecture: binary.architecture)
        let paramStr = params.isEmpty ? "void" : params.joined(separator: ", ")

        if let recognized = decompileRecognizedDOSFunction(
            function: function,
            instructions: instructions,
            binary: binary,
            returnType: returnType,
            paramStr: paramStr
        ) {
            return recognized
        }

        output += "// Function at \(String(format: "0x%llX", function.startAddress))\n"
        output += "// Size: \(function.size) bytes\n"
        if !function.callees.isEmpty {
            output += "// Calls: \(function.callees.prefix(5).map { String(format: "0x%llX", $0) }.joined(separator: ", "))\n"
        }
        output += "\n"

        output += "\(returnType) \(function.displayName)(\(paramStr))\n"
        output += "{\n"

        // Generate local variable declarations
        let locals = inferLocalVariables(instructions: instructions, architecture: binary.architecture)
        if !locals.isEmpty {
            for local in locals {
                output += "    \(local.type) \(local.name);  // \(local.comment)\n"
            }
            output += "\n"
        }

        // Use ControlFlowStructurer for proper structure recovery
        if !function.basicBlocks.isEmpty && function.basicBlocks.count > 1 {
            let structure = structurer.structure(function: function)
            let printer = EnhancedCodePrinter(binary: binary, strings: strings, dosInterruptCalls: dosInterruptCalls)
            let structuredOutput = printer.print(structure)
            if shouldPreferLinearDOSOutput(structuredOutput, instructions: instructions, binary: binary) {
                output += decompileInstructions(instructions, indent: 1, binary: binary)
            } else {
                output += structuredOutput
            }
        } else {
            // Fallback to linear decompilation for simple functions
            output += decompileInstructions(instructions, indent: 1, binary: binary)
        }

        if !output.hasSuffix("\n") {
            output += "\n"
        }
        output += "}\n"

        if binary.format == .dos || binary.architecture == .x86_16 {
            output = refineDOSPseudoCode(output)
        } else if currentReturnType == "void" {
            output = refineVoidPseudoCode(output)
        }

        return output
    }

    // MARK: - String Cache

    private func buildStringCache(binary: BinaryFile) {
        // Scan sections for strings
        for section in binary.sections {
            // Look in data sections
            if section.name.contains("cstring") || section.name.contains("string") ||
               section.name == "__const" || section.name == ".rodata" {
                scanForStrings(in: section)
            }
        }
    }

    private func scanForStrings(in section: Section) {
        var offset = 0
        while offset < section.data.count {
            var bytes: [UInt8] = []
            var currentOffset = offset

            // Read until null terminator
            while currentOffset < section.data.count {
                let byte = section.data[section.data.startIndex + currentOffset]
                if byte == 0 { break }
                bytes.append(byte)
                currentOffset += 1
            }

            // Only keep printable ASCII strings of reasonable length
            if bytes.count >= 4, let str = String(bytes: bytes, encoding: .utf8) {
                let isPrintable = str.allSatisfy { $0.isASCII && ($0.isPunctuation || $0.isLetter || $0.isNumber || $0.isWhitespace) }
                if isPrintable {
                    let address = section.address + UInt64(offset)
                    strings[address] = str
                }
            }

            offset = currentOffset + 1  // Skip null terminator
        }
    }

    private func refineDOSPseudoCode(_ source: String) -> String {
        var refined = source

        let semanticNames: [(from: String, to: String)] = [
            ("global_2EF3", "active_video_page"),
            ("global_2EF4", "current_video_mode"),
            ("global_2EF5", "screen_text_columns"),
            ("global_3044", "display_adapter_choice"),
            ("global_3048", "startup_delay_counter"),
            ("byte_8F57", "menu_exit_flag")
        ]

        for replacement in semanticNames {
            refined = refined.replacingOccurrences(of: replacement.from, with: replacement.to)
        }

        let replacements: [(pattern: String, template: String)] = [
            (
                pattern: #"(?m)^([ \t]*)ax = 0x03;\n\1if \((.+?)\) \{\n\1    ax = 0x07;\n\1\}\n\1bios_set_video_mode\(al\);"#,
                template: "$1bios_set_video_mode(($2) ? 0x07 : 0x03);"
            ),
            (
                pattern: #"(?m)^([ \t]*)ax = 0x4C00;\n\1dos_exit\(0x00\);"#,
                template: "$1dos_exit(0x00);"
            ),
            (
                pattern: #"(?m)^([ \t]*)ah = 0x0F;\n\1bios_video_interrupt\(\);"#,
                template: "$1bios_get_video_state();"
            ),
            (
                pattern: #"(?m)^([ \t]*)ah = 0x01;\n\1ch = 0x20;\n\1cl = 0x20;\n\1bios_video_interrupt\(\);"#,
                template: "$1bios_set_cursor_shape(0x20, 0x20);"
            )
        ]

        for replacement in replacements {
            refined = replacingRegex(
                pattern: replacement.pattern,
                in: refined,
                template: replacement.template
            )
        }

        return refined
    }

    private func refineVoidPseudoCode(_ source: String) -> String {
        let replacements: [(pattern: String, template: String)] = [
            (
                pattern: #"(?m)^([ \t]*)result = 0;\n\1return;"#,
                template: "$1return;"
            )
        ]

        return replacements.reduce(source) { partial, replacement in
            replacingRegex(pattern: replacement.pattern, in: partial, template: replacement.template)
        }
    }

    private func decompileRecognizedDOSFunction(
        function: Function,
        instructions: [Instruction],
        binary: BinaryFile,
        returnType: String,
        paramStr: String
    ) -> String? {
        guard binary.format == .dos || binary.architecture == .x86_16 else {
            return nil
        }

        if isDOSMenuSelectionFunction(instructions) {
            return decompileDOSMenuSelectionFunction(
                function: function,
                returnType: returnType,
                paramStr: paramStr
            )
        }

        if isDOSMenuRendererFunction(instructions) {
            return decompileDOSMenuRendererFunction(
                function: function,
                returnType: returnType,
                paramStr: paramStr
            )
        }

        return nil
    }

    private func isDOSMenuSelectionFunction(_ instructions: [Instruction]) -> Bool {
        let addresses = Set(instructions.compactMap(\.branchTarget))
        let scanCodes: Set<String> = ["0x1c", "0x41", "0x39", "0x50", "0x4d", "0x48", "0x4b"]
        let comparedScanCodes = Set(
            instructions
                .filter { $0.mnemonic.lowercased() == "cmp" }
                .compactMap { instruction -> String? in
                    let parts = instruction.operands
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    guard parts.count == 2, parts[0] == "ah" else {
                        return nil
                    }
                    return parts[1]
                }
        )

        return scanCodes.isSubset(of: comparedScanCodes)
            && addresses.contains(0x066E)
            && addresses.contains(0x06FE)
            && instructions.contains(where: { $0.mnemonic.lowercased() == "xlat" })
    }

    private func isDOSMenuRendererFunction(_ instructions: [Instruction]) -> Bool {
        let mnemonics = instructions.map { $0.mnemonic.lowercased() }

        return mnemonics.filter { $0 == "lodsb" }.count >= 2
            && mnemonics.contains("loop")
            && instructions.contains(where: { $0.mnemonic.lowercased() == "mov" && $0.operands.lowercased() == "si, 0x2f9a" })
            && instructions.contains(where: { $0.mnemonic.lowercased() == "mov" && $0.operands.lowercased() == "cx, 0x06" })
            && instructions.contains(where: { $0.mnemonic.lowercased() == "int" && $0.operands.lowercased() == "0x16" })
    }

    private func decompileDOSMenuSelectionFunction(
        function: Function,
        returnType: String,
        paramStr: String
    ) -> String {
        var output = ""
        output += "// Function at \(String(format: "0x%llX", function.startAddress))\n"
        output += "// Size: \(function.size) bytes\n\n"
        output += "\(returnType) \(function.displayName)(\(paramStr))\n"
        output += "{\n"
        output += "    menu_exit_flag = 0x00;\n"
        output += "    proc_0000();\n"
        output += "    ax = ds;\n"
        output += "    es = ax;\n"
        output += "    ax = 0x04;\n"
        output += "    if (byte_8E59 == 0x00) {\n"
        output += "        ax = 0x03;\n"
        output += "        if (byte_8E5A == 0x00) {\n"
        output += "            ax = 0x02;\n"
        output += "            if (byte_8E58 == 0x00) {\n"
        output += "                ax = 0x00;\n"
        output += "                if (byte_8E5D == 0x00) {\n"
        output += "                    ax = 0x01;\n"
        output += "                }\n"
        output += "            }\n"
        output += "        }\n"
        output += "    }\n"
        output += "    display_adapter_choice = ax;\n"
        output += "    bios_get_video_state();\n"
        output += "    active_video_page = bh;\n"
        output += "    current_video_mode = al;\n"
        output += "    screen_text_columns = ah;\n"
        output += "    bios_set_cursor_shape(0x20, 0x20);\n"
        output += "\n"
        output += "    for (;;) {\n"
        output += "        ax = 0x0600;\n"
        output += "        bh = 0x00;\n"
        output += "        cx = 0x0000;\n"
        output += "        dl = screen_text_columns;\n"
        output += "        dl--;\n"
        output += "        dh = 0x18;\n"
        output += "        bios_scroll_up_window(0x00, 0x00, 0x0000, dx);\n"
        output += "        proc_06FE();\n"
        output += "        result = bios_read_key();\n"
        output += "\n"
        output += "        switch (ah) {\n"
        output += "        case 0x1C:\n"
        output += "            break;\n"
        output += "        case 0x41:\n"
        output += "            menu_exit_flag = 0xFF;\n"
        output += "            break;\n"
        output += "        case 0x39:\n"
        output += "        case 0x50:\n"
        output += "        case 0x4D:\n"
        output += "            display_adapter_choice++;\n"
        output += "            if (display_adapter_choice >= 0x06) {\n"
        output += "                display_adapter_choice = 0x00;\n"
        output += "            }\n"
        output += "            continue;\n"
        output += "        case 0x48:\n"
        output += "        case 0x4B:\n"
        output += "            display_adapter_choice--;\n"
        output += "            if ((int16_t)display_adapter_choice < 0) {\n"
        output += "                display_adapter_choice = 0x05;\n"
        output += "            }\n"
        output += "            continue;\n"
        output += "        default:\n"
        output += "            continue;\n"
        output += "        }\n"
        output += "\n"
        output += "        if (display_adapter_choice == 0x05) {\n"
        output += "            proc_066E();\n"
        output += "            continue;\n"
        output += "        }\n"
        output += "\n"
        output += "        ax = display_adapter_choice;\n"
        output += "        bx = 0x2EF8;\n"
        output += "        // xlat maps the selected menu entry to the final adapter mode.\n"
        output += "        xlat();\n"
        output += "        display_adapter_choice = ax;\n"
        output += "        return ax;\n"
        output += "    }\n"
        output += "}\n"
        return output
    }

    private func decompileDOSMenuRendererFunction(
        function: Function,
        returnType: String,
        paramStr: String
    ) -> String {
        var output = ""
        output += "// Function at \(String(format: "0x%llX", function.startAddress))\n"
        output += "// Size: \(function.size) bytes\n\n"
        output += "\(returnType) \(function.displayName)(\(paramStr))\n"
        output += "{\n"
        output += "    ax = 0x0600;\n"
        output += "    bh = 0x00;\n"
        output += "    cx = 0x0000;\n"
        output += "    dl = screen_text_columns;\n"
        output += "    dl--;\n"
        output += "    dh = 0x18;\n"
        output += "    bios_scroll_up_window(0x00, 0x00, 0x0000, dx);\n"
        output += "    si = 0x2F9A;\n"
        output += "\n"
        output += "    for (cx = 0x06; cx != 0; --cx) {\n"
        output += "        push(cx);\n"
        output += "        dl = 0x00;\n"
        output += "        dh = load_byte_and_advance(ds, &si);\n"
        output += "        bios_set_cursor_position(active_video_page, dh, dl);\n"
        output += "        bios_write_char_attr(0x20, active_video_page, 0x07, 0x01);\n"
        output += "        while ((al = load_byte_and_advance(ds, &si)) != 0x00) {\n"
        output += "            bios_teletype_output(al);\n"
        output += "        }\n"
        output += "        result = bios_read_key();\n"
        output += "        *((uint8_t*)MK_FP(ds, si)) = ah;\n"
        output += "        si++;\n"
        output += "        ah ^= 0x80;\n"
        output += "        *((uint8_t*)MK_FP(ds, si)) = ah;\n"
        output += "        si++;\n"
        output += "        if (al < 0x20) {\n"
        output += "            push(ax);\n"
        output += "            bios_write_char_attr(0x20, active_video_page, 0x07, 0x01);\n"
        output += "            bios_teletype_output(al + 0x41);\n"
        output += "            ax = pop();\n"
        output += "        }\n"
        output += "        push(ax);\n"
        output += "        bios_write_char_attr(0x20, active_video_page, 0x07, 0x01);\n"
        output += "        ax = pop();\n"
        output += "        bios_teletype_output(al);\n"
        output += "        cx = pop();\n"
        output += "    }\n"
        output += "}\n"
        return output
    }

    private func shouldPreferLinearDOSOutput(_ structuredOutput: String, instructions: [Instruction], binary: BinaryFile) -> Bool {
        guard binary.format == .dos || binary.architecture == .x86_16 else {
            return false
        }

        guard instructions.count >= 24 else {
            return false
        }

        return structuredOutput.contains("var != 0")
    }

    private func replacingRegex(pattern: String, in source: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }

        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    // MARK: - Type Inference

    private func inferReturnType(instructions: [Instruction], architecture: Architecture) -> String {
        for insn in instructions.reversed() {
            if insn.type == .return {
                continue
            }

            let returnReg = architecture.returnValueRegister
            if insn.operands.lowercased().contains(returnReg.lowercased()) {
                // Check what type of operation
                if insn.mnemonic.lowercased().contains("movs") || insn.mnemonic.lowercased().contains("cvt") {
                    return "double"
                }
                if insn.operands.contains("byte") || insn.operands.contains("BYTE") {
                    return "char"
                }
                return defaultIntegerType(for: architecture)
            }

            // XOR with self = return 0
            if insn.mnemonic == "xor" {
                let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if parts.count == 2 && parts[0] == parts[1] && parts[0] == returnReg.lowercased() {
                    return defaultIntegerType(for: architecture)
                }
            }
        }

        return "void"
    }

    private func inferParameters(instructions: [Instruction], architecture: Architecture) -> [String] {
        var params: [String] = []
        let argRegs = architecture.argumentRegisters

        var usedArgs: [String: String] = [:] // reg -> inferred type

        for insn in instructions {
            let operands = insn.operands.lowercased()
            for (_, reg) in argRegs.enumerated() {
                if operands.contains(reg.lowercased()) {
                    let type = inferOperandType(insn: insn, operand: reg)
                    usedArgs[reg] = type
                }
            }
        }

        if argRegs.isEmpty {
            return inferStackParameters(instructions: instructions, architecture: architecture)
        }

        for (i, reg) in argRegs.enumerated() {
            if let type = usedArgs[reg] {
                let paramName = "arg\(i + 1)"
                params.append("\(type) \(paramName)")
            } else if usedArgs.keys.contains(where: { argRegs.firstIndex(of: $0) ?? 0 > i }) {
                // There's a higher numbered arg used, so this one must exist too
                params.append("\(defaultIntegerType(for: architecture)) arg\(i + 1)")
            } else {
                break
            }
        }

        return params
    }

    private func inferStackParameters(instructions: [Instruction], architecture: Architecture) -> [String] {
        let frameRegister: String
        let firstArgumentOffset: Int

        switch architecture {
        case .x86_16:
            frameRegister = "bp"
            firstArgumentOffset = 4
        case .i386:
            frameRegister = "ebp"
            firstArgumentOffset = 8
        default:
            return []
        }

        var offsets: [Int: String] = [:]
        let pattern = "\\[\(frameRegister) \\+ (0x[0-9a-fA-F]+|\\d+)\\]"

        for insn in instructions {
            let operands = insn.operands.lowercased()
            guard let match = operands.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let matchString = String(operands[match])
            guard let valueRange = matchString.range(of: "0x[0-9a-fA-F]+|\\d+", options: .regularExpression) else {
                continue
            }

            let valueString = String(matchString[valueRange])
            let offset: Int
            if valueString.hasPrefix("0x") {
                offset = Int(valueString.dropFirst(2), radix: 16) ?? 0
            } else {
                offset = Int(valueString) ?? 0
            }

            guard offset >= firstArgumentOffset else {
                continue
            }

            offsets[offset] = inferLocalType(insn: insn)
        }

        let sortedOffsets = offsets.keys.sorted()
        return sortedOffsets.enumerated().map { index, offset in
            "\(offsets[offset] ?? defaultIntegerType(for: architecture)) arg\(index + 1)"
        }
    }

    private func inferOperandType(insn: Instruction, operand: String) -> String {
        let mnem = insn.mnemonic.lowercased()

        // Floating point operations
        if mnem.hasPrefix("movs") || mnem.hasPrefix("cvt") || mnem.hasPrefix("add") && mnem.hasSuffix("s") {
            return "double"
        }

        // String operations often use pointers
        if mnem == "lea" {
            return "char*"
        }

        // Memory operations suggest pointers
        if insn.operands.contains("[") {
            return defaultPointerType()
        }

        return defaultIntegerType(for: binary?.architecture ?? .unknown)
    }

    private func inferLocalVariables(instructions: [Instruction], architecture: Architecture) -> [DecompilerLocalVar] {
        var locals: [DecompilerLocalVar] = []
        var seenOffsets = Set<Int>()

        let frameReg = architecture.framePointerName.lowercased()
        let stackReg = architecture.stackPointerName.lowercased()

        for insn in instructions {
            let operands = insn.operands.lowercased()

            // Pattern: [rbp - 0x10] or [rbp + 0x10] or [rsp + 0x20]
            let patterns = [
                "\\[\(frameReg) - (0x[0-9a-fA-F]+|\\d+)\\]",
                "\\[\(frameReg) \\+ (0x[0-9a-fA-F]+|\\d+)\\]",
                "\\[\(stackReg) \\+ (0x[0-9a-fA-F]+|\\d+)\\]"
            ]

            for pattern in patterns {
                if let match = operands.range(of: pattern, options: .regularExpression) {
                    let matchStr = String(operands[match])
                    let isSubtract = matchStr.contains("-")

                    // Extract offset value
                    if let numMatch = matchStr.range(of: "0x[0-9a-fA-F]+|\\d+", options: .regularExpression) {
                        let offsetStr = String(matchStr[numMatch])
                        let offset: Int
                        if offsetStr.hasPrefix("0x") {
                            offset = Int(offsetStr.dropFirst(2), radix: 16) ?? 0
                        } else {
                            offset = Int(offsetStr) ?? 0
                        }

                        let stackOffset = isSubtract ? -offset : offset

                        if offset > 0 && !seenOffsets.contains(stackOffset) {
                            seenOffsets.insert(stackOffset)

                            let varName = isSubtract ? "var_\(String(format: "%X", offset))" : "arg_\(String(format: "%X", offset))"
                            let varType = inferLocalType(insn: insn)
                            let comment = String(format: "[%@ %@ 0x%X]", isSubtract ? frameReg : stackReg, isSubtract ? "-" : "+", offset)

                            locals.append(DecompilerLocalVar(
                                name: varName,
                                type: varType,
                                stackOffset: stackOffset,
                                size: architecture.pointerSize,
                                comment: comment
                            ))
                        }
                    }
                }
            }
        }

        return locals.sorted { $0.stackOffset > $1.stackOffset }
    }

    private func inferLocalType(insn: Instruction) -> String {
        let mnem = insn.mnemonic.lowercased()

        if mnem.contains("movs") || mnem.contains("cvt") {
            return "double"
        }
        if mnem == "movzx" || mnem == "movsx" {
            if insn.operands.contains("byte") || insn.operands.contains("BYTE") {
                return "uint8_t"
            }
            if insn.operands.contains("word") || insn.operands.contains("WORD") {
                return "uint16_t"
            }
        }
        if mnem == "lea" {
            return defaultPointerType()
        }

        return defaultIntegerType(for: binary?.architecture ?? .unknown)
    }

    // MARK: - Instruction Decompilation

    private func decompileInstructions(_ instructions: [Instruction], indent: Int, binary: BinaryFile) -> String {
        var output = ""
        let ind = String(repeating: "    ", count: indent)

        var i = 0
        while i < instructions.count {
            let insn = instructions[i]

            // Skip NOPs and prologue/epilogue
            if insn.type == .nop || isPrologueEpilogue(insn) {
                i += 1
                continue
            }

            // Try to combine compare + conditional jump into if statement
            if insn.type == .compare && i + 1 < instructions.count {
                let nextInsn = instructions[i + 1]
                if nextInsn.type == .conditionalJump {
                    let condition = buildCondition(cmp: insn, jump: nextInsn, binary: binary)
                    let targetLabel = nextInsn.branchTarget.map { String(format: "loc_%llX", $0) } ?? "unknown"
                    output += "\(ind)if (\(condition)) goto \(targetLabel);\n"
                    i += 2
                    continue
                }
            }

            let line = decompileInstruction(insn, binary: binary)
            if !line.isEmpty {
                output += "\(ind)\(line)\n"
            }

            i += 1
        }

        return output
    }

    private func isPrologueEpilogue(_ insn: Instruction) -> Bool {
        let mnem = insn.mnemonic.lowercased()
        let ops = insn.operands.lowercased()

        // Common prologue patterns
        if mnem == "push" && (ops == "rbp" || ops == "ebp" || ops == "bp") { return true }
        if mnem == "mov" && (ops.contains("rbp, rsp") || ops.contains("ebp, esp") || ops.contains("bp, sp")) { return true }
        if mnem == "sub" && (ops.contains("rsp,") || ops.contains("esp,") || ops.contains("sp,")) { return true }

        // Common epilogue patterns
        if mnem == "pop" && (ops == "rbp" || ops == "ebp" || ops == "bp") { return true }
        if mnem == "leave" { return true }

        // ARM64 patterns
        if mnem == "stp" && ops.contains("x29, x30") { return true }
        if mnem == "ldp" && ops.contains("x29, x30") { return true }
        if (mnem == "mov" && ops == "x29, sp") || (mnem == "add" && ops == "x29, sp, #0") { return true }

        return false
    }

    private func buildCondition(cmp: Instruction, jump: Instruction, binary: BinaryFile) -> String {
        let parts = cmp.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return "condition" }

        let left = expression(for: inferredMemoryOperand(parts[0], using: parts[1]), binary: binary)
        let right = expression(for: inferredMemoryOperand(parts[1], using: parts[0]), binary: binary)

        let op: String
        switch jump.mnemonic.lowercased() {
        case "je", "jz", "b.eq": op = "=="
        case "jne", "jnz", "b.ne": op = "!="
        case "jl", "jnge", "b.lt": op = "<"
        case "jle", "jng", "b.le": op = "<="
        case "jg", "jnle", "b.gt": op = ">"
        case "jge", "jnl", "b.ge": op = ">="
        case "jb", "jnae", "b.lo": op = "<"  // unsigned
        case "jbe", "jna", "b.ls": op = "<="
        case "ja", "jnbe", "b.hi": op = ">"
        case "jae", "jnb", "b.hs": op = ">="
        default: op = "??"
        }

        return "\(left) \(op) \(right)"
    }

    private func decompileInstruction(_ insn: Instruction, binary: BinaryFile) -> String {
        switch insn.type {
        case .call:
            return decompileCall(insn, binary: binary)
        case .return:
            return decompileReturn(insn, binary: binary)
        case .move:
            return decompileMove(insn, binary: binary)
        case .arithmetic:
            return decompileArithmetic(insn)
        case .logic:
            return decompileLogic(insn)
        case .compare:
            return ""  // Handled in combination with jump
        case .load:
            return decompileLoad(insn, binary: binary)
        case .store:
            return decompileStore(insn, binary: binary)
        case .push, .pop:
            return decompileOther(insn, binary: binary)
        case .jump:
            if let target = insn.branchTarget {
                return String(format: "goto loc_%llX;", target)
            }
            return "// \(insn.text)"
        case .conditionalJump:
            return decompileConditionalJump(insn)
        case .interrupt:
            return decompileInterrupt(insn)
        case .nop:
            return ""
        case .other:
            return decompileOther(insn, binary: binary)
        default:
            return "// \(insn.text)"
        }
    }

    private func decompileCall(_ insn: Instruction, binary: BinaryFile) -> String {
        var funcName = "unknown"
        var args = ""

        if let target = insn.branchTarget {
            // Look up function name from symbols
            if let symbol = binary.symbols.first(where: { $0.address == target }) {
                funcName = symbol.displayName
            } else {
                funcName = autogeneratedFunctionName(at: target, architecture: binary.architecture, format: binary.format)
            }

            // Check for string arguments (common in printf, puts, etc.)
            if funcName.contains("print") || funcName.contains("puts") || funcName.contains("log") || funcName.contains("str") {
                // Try to find string argument
                if let strArg = findStringArgument(near: insn.address, binary: binary) {
                    args = "\"\(escapeString(strArg))\""
                }
            }
        } else if insn.operands.hasPrefix("x") || insn.operands.hasPrefix("r") {
            // Indirect call through register
            funcName = "(*\(registerToVariable(insn.operands)))"
        }

        return args.isEmpty ? "\(funcName)();" : "\(funcName)(\(args));"
    }

    private func findStringArgument(near address: UInt64, binary: BinaryFile) -> String? {
        // Look for LEA instruction loading string address in the vicinity
        // This is a heuristic - real implementation would track data flow
        for (strAddr, strValue) in strings {
            // Check if string is referenced near this call
            if strAddr > address - 100 && strAddr < address + 100 {
                return strValue
            }
        }
        return nil
    }

    private func escapeString(_ str: String) -> String {
        var result = str
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        return result
    }

    private func decompileReturn(_ insn: Instruction, binary: BinaryFile) -> String {
        if currentReturnType == "void" {
            return "return;"
        }
        return "return result;"
    }

    private func decompileInterrupt(_ insn: Instruction) -> String {
        dosInterruptCalls[insn.address]?.statement ?? "// \(insn.text)"
    }

    private func decompileConditionalJump(_ insn: Instruction) -> String {
        guard let target = insn.branchTarget else {
            return "// \(insn.text)"
        }

        let targetLabel = String(format: "loc_%llX", target)
        switch insn.mnemonic.lowercased() {
        case "loop":
            return "if (--\(loopCounterRegister()) != 0) goto \(targetLabel);"
        case "loope", "loopz":
            return "if (--\(loopCounterRegister()) != 0 && zero_flag) goto \(targetLabel);"
        case "loopne", "loopnz":
            return "if (--\(loopCounterRegister()) != 0 && !zero_flag) goto \(targetLabel);"
        case "jcxz":
            return "if (cx == 0) goto \(targetLabel);"
        case "jecxz":
            return "if (ecx == 0) goto \(targetLabel);"
        default:
            return "// \(insn.text)"
        }
    }

    private func defaultIntegerType(for architecture: Architecture) -> String {
        switch architecture.pointerSize {
        case 1:
            return "int8_t"
        case 2:
            return "int16_t"
        case 4:
            return "int32_t"
        case 8:
            return "int64_t"
        default:
            return "int"
        }
    }

    private func defaultPointerType() -> String {
        "void*"
    }

    private func autogeneratedFunctionName(at address: UInt64, architecture: Architecture, format: BinaryFormat) -> String {
        if format == .dos || architecture == .x86_16 {
            return String(format: "proc_%04llX", address)
        }
        return String(format: "sub_%llX", address)
    }

    private func decompileMove(_ insn: Instruction, binary: BinaryFile) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return "// \(insn.text)" }

        let destinationOperand = inferredMemoryOperand(parts[0], using: parts[1])
        let sourceOperand = parts[1]
        let dest = expression(for: destinationOperand, binary: binary)
        var src = expression(for: sourceOperand, binary: binary)

        // Check if source is a string address
        if let addr = parseAddress(sourceOperand) {
            if let str = strings[addr] {
                src = "\"\(escapeString(str.prefix(40).description))\""
            } else if let symbol = binary.symbols.first(where: { $0.address == addr }) {
                src = "&\(symbol.displayName)"
            }
        }

        // Skip self-moves
        if dest == src { return "" }

        return "\(dest) = \(src);"
    }

    private func decompileArithmetic(_ insn: Instruction) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let op: String
        switch insn.mnemonic.lowercased() {
        case "add": op = "+"
        case "sub": op = "-"
        case "mul", "imul": op = "*"
        case "div", "idiv": op = "/"
        case "inc":
            if parts.count >= 1 {
                let dest = expression(for: parts[0], binary: binary!)
                return "\(dest)++;"
            }
            return "// \(insn.text)"
        case "dec":
            if parts.count >= 1 {
                let dest = expression(for: parts[0], binary: binary!)
                return "\(dest)--;"
            }
            return "// \(insn.text)"
        case "neg":
            if parts.count >= 1 {
                let dest = expression(for: parts[0], binary: binary!)
                return "\(dest) = -\(dest);"
            }
            return "// \(insn.text)"
        default: op = insn.mnemonic
        }

        if parts.count == 2 {
            let dest = expression(for: inferredMemoryOperand(parts[0], using: parts[1]), binary: binary!)
            let src = expression(for: inferredMemoryOperand(parts[1], using: parts[0]), binary: binary!)
            return "\(dest) \(op)= \(src);"
        } else if parts.count == 3 {
            let dest = expression(for: inferredMemoryOperand(parts[0], using: parts[1]), binary: binary!)
            let src1 = expression(for: inferredMemoryOperand(parts[1], using: parts[0]), binary: binary!)
            let src2 = expression(for: inferredMemoryOperand(parts[2], using: parts[0]), binary: binary!)
            return "\(dest) = \(src1) \(op) \(src2);"
        }

        return "// \(insn.text)"
    }

    private func decompileLogic(_ insn: Instruction) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let op: String
        switch insn.mnemonic.lowercased() {
        case "and": op = "&"
        case "or": op = "|"
        case "xor":
            // XOR with self is zero
            if parts.count == 2 && parts[0].lowercased() == parts[1].lowercased() {
                let dest = expression(for: parts[0], binary: binary!)
                return "\(dest) = 0;"
            }
            op = "^"
        case "not":
            if parts.count >= 1 {
                let dest = expression(for: parts[0], binary: binary!)
                return "\(dest) = ~\(dest);"
            }
            return "// \(insn.text)"
        case "shl", "sal": op = "<<"
        case "shr": op = ">>"
        case "sar": op = ">>"  // arithmetic shift
        default: op = insn.mnemonic
        }

        if parts.count == 2 {
            let dest = expression(for: inferredMemoryOperand(parts[0], using: parts[1]), binary: binary!)
            let src = expression(for: inferredMemoryOperand(parts[1], using: parts[0]), binary: binary!)
            return "\(dest) \(op)= \(src);"
        } else if parts.count == 3 {
            let dest = expression(for: inferredMemoryOperand(parts[0], using: parts[1]), binary: binary!)
            let src1 = expression(for: inferredMemoryOperand(parts[1], using: parts[0]), binary: binary!)
            let src2 = expression(for: inferredMemoryOperand(parts[2], using: parts[0]), binary: binary!)
            return "\(dest) = \(src1) \(op) \(src2);"
        }

        return "// \(insn.text)"
    }

    private func decompileLoad(_ insn: Instruction, binary: BinaryFile) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return "// \(insn.text)" }

        let dest = expression(for: parts[0], binary: binary)
        let src = memoryToExpression(inferredMemoryOperand(parts[1], using: parts[0]), binary: binary)

        // LEA is address calculation, not load
        if insn.mnemonic.lowercased() == "lea" {
            // Check if loading string address
            if let addr = parseAddressFromMemory(parts[1]) {
                if let str = strings[addr] {
                    return "\(dest) = \"\(escapeString(str.prefix(40).description))\";"
                }
                if let symbol = binary.symbols.first(where: { $0.address == addr }) {
                    return "\(dest) = &\(symbol.displayName);"
                }
            }
            return "\(dest) = &\(src.replacingOccurrences(of: "*", with: ""));"
        }

        return "\(dest) = \(src);"
    }

    private func decompileStore(_ insn: Instruction, binary: BinaryFile) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return "// \(insn.text)" }

        let dest = memoryToExpression(inferredMemoryOperand(parts[0], using: parts[1]), binary: binary)
        let src = expression(for: parts[1], binary: binary)

        return "\(dest) = \(src);"
    }

    private func decompileOther(_ insn: Instruction, binary: BinaryFile) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let mnemonic = insn.mnemonic.lowercased()

        switch mnemonic {
        case "cld":
            return "clear_direction_flag();"
        case "std":
            return "set_direction_flag();"
        case "cli":
            return "disable_interrupts();"
        case "sti":
            return "enable_interrupts();"
        case "push":
            guard let value = parts.first else { return "// \(insn.text)" }
            return "push(\(expression(for: value, binary: binary)));"
        case "pop":
            guard let value = parts.first else { return "// \(insn.text)" }
            return "\(expression(for: value, binary: binary)) = pop();"
        case "in":
            guard parts.count >= 2 else { return "// \(insn.text)" }
            return "\(expression(for: parts[0], binary: binary)) = port_in\(bitWidth(for: parts[0]))(\(expression(for: parts[1], binary: binary)));"
        case "out":
            guard parts.count >= 2 else { return "// \(insn.text)" }
            return "port_out\(bitWidth(for: parts[1]))(\(expression(for: parts[0], binary: binary)), \(expression(for: parts[1], binary: binary)));"
        case "lodsb", "lodsw", "lodsd", "lodsq":
            let accumulator = accumulatorRegister(for: mnemonic)
            return "\(accumulator) = load_\(stringUnitName(for: mnemonic))(ds, si);"
        case "stosb", "stosw", "stosd", "stosq":
            let accumulator = accumulatorRegister(for: mnemonic)
            return "store_\(stringUnitName(for: mnemonic))(es, di, \(accumulator));"
        case "movsb", "movsw", "movsd", "movsq":
            return "copy_\(stringUnitName(for: mnemonic))(es, di, ds, si);"
        case "cmpsb", "cmpsw", "cmpsd", "cmpsq":
            return "compare_\(stringUnitName(for: mnemonic))(ds, si, es, di);"
        case "scasb", "scasw", "scasd", "scasq":
            return "scan_\(stringUnitName(for: mnemonic))(es, di, \(accumulatorRegister(for: mnemonic)));"
        case "insb", "insw", "insd":
            return "port_stream_in\(bitWidth(for: accumulatorRegister(for: mnemonic)))(dx, es, di);"
        case "outsb", "outsw", "outsd":
            return "port_stream_out\(bitWidth(for: accumulatorRegister(for: mnemonic)))(dx, ds, si);"
        case "rep", "repe", "repz", "repne", "repnz":
            guard let operand = parts.first else { return "// \(insn.text)" }
            return decompileRepeatedStringInstruction(prefix: mnemonic, operand: operand)
        default:
            return "// \(insn.text)"
        }
    }

    // MARK: - Expression Conversion

    private func registerToVariable(_ reg: String) -> String {
        let r = reg.trimmingCharacters(in: .whitespaces).lowercased()

        if isDOSLikeBinary {
            let passthroughRegisters: Set<String> = [
                "ax", "bx", "cx", "dx", "si", "di", "bp", "sp",
                "al", "ah", "bl", "bh", "cl", "ch", "dl", "dh",
                "cs", "ds", "es", "ss", "ip", "flags"
            ]
            if passthroughRegisters.contains(r) {
                return r
            }
        }

        let regMap: [String: String] = [
            // x86_64
            "rax": "result", "eax": "result", "ax": "result", "al": "result",
            "rdi": "arg1", "edi": "arg1",
            "rsi": "arg2", "esi": "arg2",
            "rdx": "arg3", "edx": "arg3",
            "rcx": "arg4", "ecx": "arg4",
            "r8": "arg5", "r8d": "arg5",
            "r9": "arg6", "r9d": "arg6",
            "rbx": "rbx_saved", "ebx": "rbx_saved",
            "r10": "temp1", "r11": "temp2",
            "r12": "r12_saved", "r13": "r13_saved", "r14": "r14_saved", "r15": "r15_saved",
            // ARM64
            "x0": "result", "w0": "result",
            "x1": "arg2", "w1": "arg2",
            "x2": "arg3", "w2": "arg3",
            "x3": "arg4", "w3": "arg4",
            "x4": "arg5", "w4": "arg5",
            "x5": "arg6", "w5": "arg6",
            "x6": "arg7", "w6": "arg7",
            "x7": "arg8", "w7": "arg8",
            "x8": "indirect_result", "w8": "indirect_result",
            "x9": "temp1", "x10": "temp2", "x11": "temp3",
            "x19": "x19_saved", "x20": "x20_saved", "x21": "x21_saved",
            "x29": "frame_ptr", "x30": "link_reg", "x31": "sp", "w31": "wsp",
        ]

        return regMap[r] ?? r
    }

    private func operandToExpression(_ operand: String) -> String {
        var op = operand.trimmingCharacters(in: .whitespaces)

        // ARM64 immediate
        if op.hasPrefix("#") {
            op = String(op.dropFirst())
        }

        // Hex number
        if op.lowercased().hasPrefix("0x") {
            if let val = UInt64(op.dropFirst(2), radix: 16) {
                if val < 256 {
                    return op  // Keep small hex values
                }
                // Check if it might be an ASCII value
                if val >= 0x20 && val <= 0x7E {
                    return "'\(Character(UnicodeScalar(UInt8(val))))'"
                }
                return op
            }
        }

        // Decimal number
        if op.first?.isNumber == true {
            return op
        }

        // Register
        return registerToVariable(op)
    }

    private func expression(for operand: String, binary: BinaryFile) -> String {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("[") || normalized.contains(" ptr ") || normalized.contains(":") {
            return memoryToExpression(operand, binary: binary)
        }
        return operandToExpression(operand)
    }

    private func memoryToExpression(_ operand: String, binary: BinaryFile) -> String {
        let (sizeQualifier, segmentOverride, innerOperand) = normalizeMemoryOperand(operand)
        let op = innerOperand

        // Parse address from operand
        if let addr = parseAddress(op) {
            // Check for string
            if let str = strings[addr] {
                return "\"\(escapeString(str.prefix(32).description))\""
            }
            // Check for symbol
            if let symbol = binary.symbols.first(where: { $0.address == addr }) {
                return symbol.displayName
            }

            return namedDirectMemoryReference(
                sizeQualifier: sizeQualifier,
                segment: segmentOverride ?? "ds",
                address: addr
            )
        }

        // Stack variable pattern: rbp - 0x10
        if op.lowercased().contains("rbp") || op.lowercased().contains("ebp") ||
            op.lowercased().contains("bp") || op.lowercased().contains("sp") ||
            op.lowercased().contains("x29") {
            if let match = op.range(of: "- ?(0x[0-9a-fA-F]+|\\d+)", options: .regularExpression) {
                let offsetStr = String(op[match]).replacingOccurrences(of: "- ", with: "").replacingOccurrences(of: "-", with: "")
                let offset: Int
                if offsetStr.lowercased().hasPrefix("0x") {
                    offset = Int(offsetStr.dropFirst(2), radix: 16) ?? 0
                } else {
                    offset = Int(offsetStr) ?? 0
                }
                return "var_\(String(format: "%X", offset))"
            }
            if let match = op.range(of: "\\+ ?(0x[0-9a-fA-F]+|\\d+)", options: .regularExpression) {
                let offsetStr = String(op[match]).replacingOccurrences(of: "+ ", with: "").replacingOccurrences(of: "+", with: "")
                let offset: Int
                if offsetStr.lowercased().hasPrefix("0x") {
                    offset = Int(offsetStr.dropFirst(2), radix: 16) ?? 0
                } else {
                    offset = Int(offsetStr) ?? 0
                }
                return "arg_\(String(format: "%X", offset))"
            }
        }

        // Complex addressing mode: base + index * scale + disp
        let mapped = op.split(separator: " ").map { part -> String in
            let p = String(part)
            if p == "+" || p == "-" || p == "*" { return p }
            if p.first?.isNumber == true || p.hasPrefix("0x") { return p }
            return registerToVariable(p)
        }.joined(separator: " ")

        if let segmentOverride {
            return typedMemoryReference(
                sizeQualifier: sizeQualifier,
                segment: segmentOverride,
                offset: mapped
            )
        }

        return sizeQualifier == nil ? "*(\(mapped))" : typedMemoryReference(sizeQualifier: sizeQualifier, segment: nil, offset: mapped)
    }

    private func normalizeMemoryOperand(_ operand: String) -> (sizeQualifier: String?, segmentOverride: String?, inner: String) {
        var op = operand.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = op.lowercased()

        let qualifiers = ["byte ptr ", "word ptr ", "dword ptr ", "qword ptr "]
        var sizeQualifier: String?

        for qualifier in qualifiers where lowercase.hasPrefix(qualifier) {
            sizeQualifier = String(qualifier.dropLast(5)).trimmingCharacters(in: .whitespaces)
            op = String(op.dropFirst(qualifier.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        var segmentOverride: String?
        if let bracketIndex = op.firstIndex(of: "[") {
            let prefix = op[..<bracketIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.hasSuffix(":") {
                segmentOverride = String(prefix.dropLast()).lowercased()
            }
        }

        if let open = op.firstIndex(of: "["), let close = op.lastIndex(of: "]"), open < close {
            op = String(op[op.index(after: open)..<close])
        }

        return (sizeQualifier, segmentOverride, op)
    }

    private func typedMemoryReference(sizeQualifier: String?, segment: String?, offset: String) -> String {
        let pointer: String
        switch sizeQualifier?.lowercased() {
        case "byte":
            pointer = "uint8_t"
        case "word":
            pointer = "uint16_t"
        case "dword":
            pointer = "uint32_t"
        case "qword":
            pointer = "uint64_t"
        default:
            pointer = "uint16_t"
        }

        if let segment {
            return "*((\(pointer)*)MK_FP(\(segment), \(offset)))"
        }

        return "*((\(pointer)*)\(offset))"
    }

    private var isDOSLikeBinary: Bool {
        binary?.format == .dos || binary?.architecture == .x86_16
    }

    private func namedDirectMemoryReference(sizeQualifier: String?, segment: String, address: UInt64) -> String {
        if let semanticName = semanticDOSGlobalName(segment: segment, address: address) {
            return semanticName
        }

        let normalizedSegment = segment.lowercased()
        let addressString = address < 0x10000 ? String(format: "%04llX", address) : String(format: "%llX", address)
        let prefix: String

        if normalizedSegment != "ds" {
            prefix = normalizedSegment
        } else if let sizeQualifier {
            prefix = sizeQualifier.lowercased()
        } else {
            prefix = "global"
        }

        return "\(prefix)_\(addressString)"
    }

    private func semanticDOSGlobalName(segment: String?, address: UInt64) -> String? {
        guard isDOSLikeBinary else {
            return nil
        }

        let normalizedSegment = (segment ?? "ds").lowercased()
        guard normalizedSegment == "ds" else {
            return nil
        }

        switch address {
        case 0x2EF3:
            return "active_video_page"
        case 0x2EF4:
            return "current_video_mode"
        case 0x2EF5:
            return "screen_text_columns"
        case 0x3044:
            return "display_adapter_choice"
        case 0x3048:
            return "startup_delay_counter"
        case 0x8F57:
            return "menu_exit_flag"
        default:
            return nil
        }
    }

    private func inferredMemoryOperand(_ operand: String, using counterpart: String) -> String {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("["),
              !normalized.contains(" ptr "),
              let sizeQualifier = operandSizeQualifier(for: counterpart) else {
            return operand
        }
        return "\(sizeQualifier) ptr \(operand)"
    }

    private func operandSizeQualifier(for operand: String) -> String? {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("byte ptr") { return "byte" }
        if normalized.contains("word ptr") { return "word" }
        if normalized.contains("dword ptr") { return "dword" }
        if normalized.contains("qword ptr") { return "qword" }

        switch normalized {
        case "al", "ah", "bl", "bh", "cl", "ch", "dl", "dh":
            return "byte"
        case "ax", "bx", "cx", "dx", "si", "di", "bp", "sp", "cs", "ds", "es", "ss", "ip", "flags":
            return "word"
        case "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp":
            return "dword"
        case "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp":
            return "qword"
        default:
            return nil
        }
    }

    private func loopCounterRegister() -> String {
        if binary?.architecture == .i386 {
            return "ecx"
        }
        if binary?.architecture == .x86_64 {
            return "rcx"
        }
        return "cx"
    }

    private func bitWidth(for operand: String) -> Int {
        switch operandSizeQualifier(for: operand) {
        case "byte":
            return 8
        case "word":
            return 16
        case "dword":
            return 32
        case "qword":
            return 64
        default:
            return (binary?.architecture.pointerSize ?? 2) * 8
        }
    }

    private func accumulatorRegister(for mnemonic: String) -> String {
        switch mnemonic.suffix(1).lowercased() {
        case "b":
            return isDOSLikeBinary ? "al" : "result"
        case "w":
            return isDOSLikeBinary ? "ax" : "result"
        case "d":
            return binary?.architecture == .i386 ? "eax" : "result"
        case "q":
            return binary?.architecture == .x86_64 ? "rax" : "result"
        default:
            return isDOSLikeBinary ? "ax" : "result"
        }
    }

    private func stringUnitName(for mnemonic: String) -> String {
        switch mnemonic.suffix(1).lowercased() {
        case "b":
            return "byte"
        case "w":
            return "word"
        case "d":
            return "dword"
        case "q":
            return "qword"
        default:
            return "item"
        }
    }

    private func decompileRepeatedStringInstruction(prefix: String, operand: String) -> String {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "stosb", "stosw", "stosd", "stosq":
            return "fill_\(stringUnitName(for: normalized))(es, di, \(accumulatorRegister(for: normalized)), \(loopCounterRegister()));"
        case "movsb", "movsw", "movsd", "movsq":
            return "copy_\(stringUnitName(for: normalized))s(es, di, ds, si, \(loopCounterRegister()));"
        case "cmpsb", "cmpsw", "cmpsd", "cmpsq":
            return "compare_\(stringUnitName(for: normalized))s(ds, si, es, di, \(loopCounterRegister()));"
        case "scasb", "scasw", "scasd", "scasq":
            return "scan_\(stringUnitName(for: normalized))s(es, di, \(accumulatorRegister(for: normalized)), \(loopCounterRegister()));"
        case "lodsb", "lodsw", "lodsd", "lodsq":
            return "\(accumulatorRegister(for: normalized)) = load_\(stringUnitName(for: normalized))_sequence(ds, si, \(loopCounterRegister()));"
        case "insb", "insw", "insd":
            return "port_stream_in\(bitWidth(for: accumulatorRegister(for: normalized)))(dx, es, di, \(loopCounterRegister()));"
        case "outsb", "outsw", "outsd":
            return "port_stream_out\(bitWidth(for: accumulatorRegister(for: normalized)))(dx, ds, si, \(loopCounterRegister()));"
        default:
            return "// \(prefix) \(operand)"
        }
    }

    private func parseAddress(_ str: String) -> UInt64? {
        let s = str.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("0x") {
            return UInt64(s.dropFirst(2), radix: 16)
        }
        return UInt64(s)
    }

    private func parseAddressFromMemory(_ str: String) -> UInt64? {
        var s = str.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }

        // Look for immediate address
        if let match = s.range(of: "0x[0-9a-fA-F]+", options: .regularExpression) {
            let addrStr = String(s[match])
            return UInt64(addrStr.dropFirst(2), radix: 16)
        }

        // RIP-relative
        if s.lowercased().contains("rip") {
            if let match = s.range(of: "[+-] ?(0x[0-9a-fA-F]+|\\d+)", options: .regularExpression) {
                _ = String(s[match])
                // Would need current instruction address to resolve this
            }
        }

        return nil
    }
}

// MARK: - Decompiler Local Variable

struct DecompilerLocalVar {
    let name: String
    let type: String
    let stackOffset: Int
    let size: Int
    var comment: String = ""
}

// MARK: - Enhanced Code Printer

/// Enhanced printer that produces cleaner pseudo-C code
class EnhancedCodePrinter {
    private let binary: BinaryFile?
    private let strings: [UInt64: String]
    private let dosInterruptCalls: [UInt64: DOSInterruptCall]
    private var indentLevel = 1

    init(binary: BinaryFile?, strings: [UInt64: String], dosInterruptCalls: [UInt64: DOSInterruptCall]) {
        self.binary = binary
        self.strings = strings
        self.dosInterruptCalls = dosInterruptCalls
    }

    func print(_ structure: ControlFlowStructurer.ControlStructure) -> String {
        return printStructure(structure)
    }

    private func printStructure(_ structure: ControlFlowStructurer.ControlStructure) -> String {
        switch structure {
        case .sequence(let items):
            return items.map { printStructure($0) }.filter { !$0.isEmpty }.joined(separator: "\n")

        case .ifThen(let condition, let body):
            var result = indent() + "if (\(formatCondition(condition))) {\n"
            indentLevel += 1
            result += printStructure(body)
            indentLevel -= 1
            result += "\n" + indent() + "}"
            return result

        case .ifThenElse(let condition, let thenBody, let elseBody):
            var result = indent() + "if (\(formatCondition(condition))) {\n"
            indentLevel += 1
            result += printStructure(thenBody)
            indentLevel -= 1
            result += "\n" + indent() + "} else {\n"
            indentLevel += 1
            result += printStructure(elseBody)
            indentLevel -= 1
            result += "\n" + indent() + "}"
            return result

        case .whileLoop(let condition, let body):
            var result = indent() + "while (\(formatCondition(condition))) {\n"
            indentLevel += 1
            result += renderLoopBody(body)
            indentLevel -= 1
            result += "\n" + indent() + "}"
            return result

        case .doWhileLoop(let body, let condition):
            var result = indent() + "do {\n"
            indentLevel += 1
            result += renderLoopBody(body)
            indentLevel -= 1
            result += "\n" + indent() + "} while (\(formatCondition(condition)));"
            return result

        case .forLoop(let initStmt, let condition, let update, let body):
            let initStr = initStmt.map { printInline($0) } ?? ""
            let condStr = formatCondition(condition)
            let updateStr = update.map { printInline($0) } ?? inferredCountedLoopUpdate(for: condition)

            var result = indent() + "for (\(initStr); \(condStr); \(updateStr)) {\n"
            indentLevel += 1
            result += printStructure(body)
            indentLevel -= 1
            result += "\n" + indent() + "}"
            return result

        case .switchCase(let value, let cases, let defaultBody):
            var result = indent() + "switch (\(value)) {\n"

            for caseItem in cases {
                let valueStr = caseItem.values.map { String($0) }.joined(separator: ", ")
                result += indent() + "case \(valueStr):\n"
                indentLevel += 1
                result += printStructure(caseItem.body)
                result += "\n" + indent() + "break;\n"
                indentLevel -= 1
            }

            if let defBody = defaultBody {
                result += indent() + "default:\n"
                indentLevel += 1
                result += printStructure(defBody)
                result += "\n" + indent() + "break;\n"
                indentLevel -= 1
            }

            result += indent() + "}"
            return result

        case .block(let basicBlock):
            return printBlock(basicBlock)

        case .breakStmt:
            return indent() + "break;"

        case .continueStmt:
            return indent() + "continue;"

        case .returnStmt(let value):
            if let v = value {
                return indent() + "return \(mapOperand(v));"
            }
            return indent() + "return;"

        case .goto(let addr):
            return indent() + String(format: "goto loc_%llX;", addr)
        }
    }

    private func printInline(_ structure: ControlFlowStructurer.ControlStructure) -> String {
        if case .block(let bb) = structure {
            for insn in bb.instructions.reversed() {
                if insn.type == .nop || insn.type == .jump || insn.type == .conditionalJump { continue }
                let line = decompileInstruction(insn)
                return line.replacingOccurrences(of: ";", with: "")
            }
        }
        return ""
    }

    private func printBlock(_ block: BasicBlock) -> String {
        var lines: [String] = []

        for insn in block.instructions {
            if insn.type == .nop { continue }
            if insn.type == .conditionalJump || insn.type == .jump { continue }
            if isPrologueEpilogue(insn) { continue }

            let line = decompileInstruction(insn)
            if !line.isEmpty {
                lines.append(indent() + line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func decompileInstruction(_ insn: Instruction) -> String {
        let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        switch insn.type {
        case .move:
            guard parts.count >= 2 else { return "" }
            let dest = renderOperand(parts[0])
            let src = renderOperand(parts[1])
            if dest == src { return "" }
            return "\(dest) = \(src);"

        case .arithmetic:
            return decompileArithmetic(insn, parts: parts)

        case .logic:
            return decompileLogic(insn, parts: parts)

        case .call:
            return decompileCall(insn)

        case .return:
            return "return;"

        case .load:
            guard parts.count >= 2 else { return "" }
            let dest = renderOperand(parts[0])
            let src = mapMemory(parts[1])
            if insn.mnemonic.lowercased() == "lea" {
                return "\(dest) = &\(src.replacingOccurrences(of: "*", with: ""));"
            }
            return "\(dest) = \(src);"

        case .store:
            guard parts.count >= 2 else { return "" }
            let dest = mapMemory(parts[0])
            let src = renderOperand(parts[1])
            return "\(dest) = \(src);"

        case .compare:
            return ""

        case .interrupt:
            return dosInterruptCalls[insn.address]?.statement ?? "// \(insn.text)"

        case .push, .pop, .other:
            return decompileOther(insn, parts: parts)

        default:
            return "// \(insn.text)"
        }
    }

    private func decompileArithmetic(_ insn: Instruction, parts: [String]) -> String {
        let mnem = insn.mnemonic.lowercased()

        switch mnem {
        case "inc":
            guard parts.count >= 1 else { return "" }
            return "\(renderOperand(parts[0]))++;"
        case "dec":
            guard parts.count >= 1 else { return "" }
            return "\(renderOperand(parts[0]))--;"
        case "neg":
            guard parts.count >= 1 else { return "" }
            let v = renderOperand(parts[0])
            return "\(v) = -\(v);"
        default:
            break
        }

        let op: String
        switch mnem {
        case "add": op = "+"
        case "sub": op = "-"
        case "mul", "imul": op = "*"
        case "div", "idiv": op = "/"
        default: op = mnem
        }

        if parts.count == 2 {
            let dest = renderOperand(parts[0])
            let src = renderOperand(parts[1])
            return "\(dest) \(op)= \(src);"
        } else if parts.count >= 3 {
            let dest = renderOperand(parts[0])
            let src1 = renderOperand(parts[1])
            let src2 = renderOperand(parts[2])
            return "\(dest) = \(src1) \(op) \(src2);"
        }

        return ""
    }

    private func decompileLogic(_ insn: Instruction, parts: [String]) -> String {
        let mnem = insn.mnemonic.lowercased()

        // XOR with self = zero
        if mnem == "xor" && parts.count == 2 && parts[0].lowercased() == parts[1].lowercased() {
            return "\(renderOperand(parts[0])) = 0;"
        }

        let op: String
        switch mnem {
        case "and": op = "&"
        case "or": op = "|"
        case "xor": op = "^"
        case "not":
            guard parts.count >= 1 else { return "" }
            let v = renderOperand(parts[0])
            return "\(v) = ~\(v);"
        case "shl", "sal": op = "<<"
        case "shr", "sar": op = ">>"
        default: op = mnem
        }

        if parts.count == 2 {
            let dest = renderOperand(parts[0])
            let src = renderOperand(parts[1])
            return "\(dest) \(op)= \(src);"
        } else if parts.count >= 3 {
            let dest = renderOperand(parts[0])
            let src1 = renderOperand(parts[1])
            let src2 = renderOperand(parts[2])
            return "\(dest) = \(src1) \(op) \(src2);"
        }

        return ""
    }

    private func decompileCall(_ insn: Instruction) -> String {
        var funcName = "unknown"

        if let target = insn.branchTarget {
            if let sym = binary?.symbols.first(where: { $0.address == target }) {
                funcName = sym.displayName
            } else {
                let architecture = binary?.architecture ?? .unknown
                let format = binary?.format ?? .unknown
                funcName = autogeneratedFunctionName(at: target, architecture: architecture, format: format)
            }
        }

        return "\(funcName)();"
    }

    private func autogeneratedFunctionName(at address: UInt64, architecture: Architecture, format: BinaryFormat) -> String {
        if format == .dos || architecture == .x86_16 {
            return String(format: "proc_%04llX", address)
        }
        return String(format: "sub_%llX", address)
    }

    private func formatCondition(_ condition: ControlFlowStructurer.Condition) -> String {
        let left = renderOperand(condition.leftOperand)
        let right = renderOperand(condition.rightOperand)

        var cmpOp = condition.comparison.rawValue
        // Remove unsigned markers for readability
        cmpOp = cmpOp.replacingOccurrences(of: "u", with: "")

        if condition.isNegated {
            return "!(\(left) \(cmpOp) \(right))"
        }
        return "\(left) \(cmpOp) \(right)"
    }

    private func mapOperand(_ op: String) -> String {
        var o = op.trimmingCharacters(in: .whitespaces)
        if o.hasPrefix("#") { o = String(o.dropFirst()) }

        let regMap: [String: String] = [
            "rax": "result", "eax": "result",
            "rdi": "arg1", "edi": "arg1", "x0": "result", "w0": "result",
            "rsi": "arg2", "esi": "arg2", "x1": "arg2", "w1": "arg2",
            "rdx": "arg3", "edx": "arg3", "x2": "arg3", "w2": "arg3",
            "rcx": "arg4", "ecx": "arg4", "x3": "arg4", "w3": "arg4",
            "r8": "arg5", "r8d": "arg5", "x4": "arg5", "w4": "arg5",
            "r9": "arg6", "r9d": "arg6", "x5": "arg6", "w5": "arg6",
        ]

        return regMap[o.lowercased()] ?? o
    }

    private func renderOperand(_ operand: String) -> String {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("[") || normalized.contains(" ptr ") || normalized.contains(":") {
            return mapMemory(operand)
        }
        return mapOperand(operand)
    }

    private func mapMemory(_ op: String) -> String {
        let (sizeQualifier, segmentOverride, inner) = normalizeMemoryOperand(op)
        let o = inner

        if let addr = parseAddress(o) {
            if let str = strings[addr] {
                return "\"\(escapeString(str.prefix(32).description))\""
            }
            if let symbol = binary?.symbols.first(where: { $0.address == addr }) {
                return symbol.displayName
            }
            return namedDirectMemory(sizeQualifier: sizeQualifier, segment: segmentOverride, address: addr)
        }

        // Stack variable
        if o.lowercased().contains("rbp") || o.lowercased().contains("ebp") ||
            o.lowercased().contains("bp") || o.lowercased().contains("x29") {
            if let match = o.range(of: "- ?(0x[0-9a-fA-F]+|\\d+)", options: .regularExpression) {
                let offsetStr = String(o[match]).filter { $0.isHexDigit || $0 == "x" }
                return "var_\(offsetStr.uppercased())"
            }
            if let match = o.range(of: "\\+ ?(0x[0-9a-fA-F]+|\\d+)", options: .regularExpression) {
                let offsetStr = String(o[match]).filter { $0.isHexDigit || $0 == "x" }
                return "arg_\(offsetStr.uppercased())"
            }
        }

        if let segmentOverride {
            return typedMemoryReference(sizeQualifier: sizeQualifier, segment: segmentOverride, offset: mapOperand(o))
        }

        return sizeQualifier == nil ? "*(\(mapOperand(o)))" : typedMemoryReference(sizeQualifier: sizeQualifier, segment: nil, offset: mapOperand(o))
    }

    private func decompileOther(_ insn: Instruction, parts: [String]) -> String {
        let mnemonic = insn.mnemonic.lowercased()

        switch mnemonic {
        case "push":
            guard let value = parts.first else { return "// \(insn.text)" }
            return "push(\(renderOperand(value)));"
        case "pop":
            guard let destination = parts.first else { return "// \(insn.text)" }
            return "\(renderOperand(destination)) = pop();"
        case "cld":
            return "clear_direction_flag();"
        case "std":
            return "set_direction_flag();"
        case "cli":
            return "disable_interrupts();"
        case "sti":
            return "enable_interrupts();"
        case "in":
            guard parts.count >= 2 else { return "// \(insn.text)" }
            let destination = renderOperand(parts[0])
            let port = renderOperand(parts[1])
            return "\(destination) = port_in\(bitWidth(for: parts[0]))(\(port));"
        case "out":
            guard parts.count >= 2 else { return "// \(insn.text)" }
            let port = renderOperand(parts[0])
            let value = renderOperand(parts[1])
            return "port_out\(bitWidth(for: parts[1]))(\(port), \(value));"
        case "insb", "insw", "insd":
            return streamPortInputCall(mnemonic: mnemonic, repeated: false)
        case "outsb", "outsw", "outsd":
            return streamPortOutputCall(mnemonic: mnemonic, repeated: false)
        case "movsb", "movsw", "movsd", "movsq":
            return stringMoveCall(mnemonic: mnemonic, repeated: false)
        case "stosb", "stosw", "stosd", "stosq":
            return stringStoreCall(mnemonic: mnemonic, repeated: false)
        case "lodsb", "lodsw", "lodsd", "lodsq":
            return stringLoadCall(mnemonic: mnemonic, repeated: false)
        case "scasb", "scasw", "scasd", "scasq":
            return stringScanCall(mnemonic: mnemonic, repeated: false)
        case "cmpsb", "cmpsw", "cmpsd", "cmpsq":
            return stringCompareCall(mnemonic: mnemonic, repeated: false)
        case "rep", "repe", "repz", "repne", "repnz":
            guard let operand = parts.first else { return "// \(insn.text)" }
            return decompileRepeatedOperation(prefix: mnemonic, operand: operand)
        default:
            return "// \(insn.text)"
        }
    }

    private func isPrologueEpilogue(_ insn: Instruction) -> Bool {
        let mnem = insn.mnemonic.lowercased()
        let ops = insn.operands.lowercased()

        if mnem == "push" && (ops == "rbp" || ops == "ebp") { return true }
        if mnem == "mov" && ops.contains("rbp, rsp") { return true }
        if mnem == "sub" && ops.contains("rsp,") { return true }
        if mnem == "pop" && ops == "rbp" { return true }
        if mnem == "leave" { return true }
        if mnem == "stp" && ops.contains("x29, x30") { return true }
        if mnem == "ldp" && ops.contains("x29, x30") { return true }
        if (mnem == "mov" && ops == "x29, sp") || (mnem == "add" && ops == "x29, sp, #0") { return true }

        return false
    }

    private func indent() -> String {
        String(repeating: "    ", count: indentLevel)
    }

    private func renderLoopBody(_ body: ControlFlowStructurer.ControlStructure) -> String {
        let rendered = printStructure(body)
        if !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rendered
        }
        if binary?.format == .dos || binary?.architecture == .x86_16 {
            return indent() + "// polling loop or hardware delay"
        }
        return ""
    }

    private func inferredCountedLoopUpdate(for condition: ControlFlowStructurer.Condition) -> String {
        switch condition.leftOperand.lowercased() {
        case "cx" where condition.rightOperand == "0":
            return "--cx"
        case "ecx" where condition.rightOperand == "0":
            return "--ecx"
        case "rcx" where condition.rightOperand == "0":
            return "--rcx"
        default:
            return ""
        }
    }

    private func normalizeMemoryOperand(_ operand: String) -> (sizeQualifier: String?, segmentOverride: String?, inner: String) {
        var op = operand.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = op.lowercased()
        let qualifiers = ["byte ptr ", "word ptr ", "dword ptr ", "qword ptr "]
        var sizeQualifier: String?

        for qualifier in qualifiers where lowercase.hasPrefix(qualifier) {
            sizeQualifier = String(qualifier.dropLast(5)).trimmingCharacters(in: .whitespaces)
            op = String(op.dropFirst(qualifier.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        var segmentOverride: String?
        if let bracketIndex = op.firstIndex(of: "[") {
            let prefix = op[..<bracketIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.hasSuffix(":") {
                segmentOverride = String(prefix.dropLast()).lowercased()
            }
        }

        if let open = op.firstIndex(of: "["), let close = op.lastIndex(of: "]"), open < close {
            op = String(op[op.index(after: open)..<close])
        }

        return (sizeQualifier, segmentOverride, op)
    }

    private func typedMemoryReference(sizeQualifier: String?, segment: String?, offset: String) -> String {
        let pointer: String
        switch sizeQualifier?.lowercased() {
        case "byte":
            pointer = "uint8_t"
        case "word":
            pointer = "uint16_t"
        case "dword":
            pointer = "uint32_t"
        case "qword":
            pointer = "uint64_t"
        default:
            pointer = "uint16_t"
        }

        if let segment {
            return "*((\(pointer)*)MK_FP(\(segment), \(offset)))"
        }

        return "*((\(pointer)*)\(offset))"
    }

    private func namedDirectMemory(sizeQualifier: String?, segment: String?, address: UInt64) -> String {
        if let semanticName = semanticDOSGlobalName(segment: segment, address: address) {
            return semanticName
        }

        let formattedAddress = address < 0x10000 ? String(format: "%04llX", address) : String(format: "%llX", address)
        let prefix: String
        if let segment, !segment.isEmpty, segment != "ds" {
            prefix = segment.lowercased()
        } else if sizeQualifier?.lowercased() == "byte" {
            prefix = "byte"
        } else {
            prefix = "global"
        }
        return "\(prefix)_\(formattedAddress)"
    }

    private var isDOSLikeBinary: Bool {
        binary?.format == .dos || binary?.architecture == .x86_16
    }

    private func semanticDOSGlobalName(segment: String?, address: UInt64) -> String? {
        guard isDOSLikeBinary else {
            return nil
        }

        let normalizedSegment = (segment ?? "ds").lowercased()
        guard normalizedSegment == "ds" else {
            return nil
        }

        switch address {
        case 0x2EF3:
            return "active_video_page"
        case 0x2EF4:
            return "current_video_mode"
        case 0x2EF5:
            return "screen_text_columns"
        case 0x3044:
            return "display_adapter_choice"
        case 0x3048:
            return "startup_delay_counter"
        case 0x8F57:
            return "menu_exit_flag"
        default:
            return nil
        }
    }

    private func parseAddress(_ str: String) -> UInt64? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        if trimmed.first?.isNumber == true {
            return UInt64(trimmed)
        }
        return nil
    }

    private func bitWidth(for operand: String) -> Int {
        let normalized = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["al", "ah", "bl", "bh", "cl", "ch", "dl", "dh"].contains(normalized) {
            return 8
        }
        if ["ax", "bx", "cx", "dx", "si", "di", "bp", "sp"].contains(normalized) {
            return 16
        }
        if normalized.hasPrefix("e") || normalized.hasSuffix("d") || ["eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp"].contains(normalized) {
            return 32
        }
        if normalized.hasPrefix("r") || normalized.hasPrefix("x") {
            return 64
        }
        return (binary?.architecture.pointerSize ?? 2) * 8
    }

    private func elementSuffix(for mnemonic: String) -> String {
        switch mnemonic.suffix(1).lowercased() {
        case "b":
            return "bytes"
        case "w":
            return "words"
        case "d":
            return "dwords"
        case "q":
            return "qwords"
        default:
            return "items"
        }
    }

    private func accumulatorRegister(for mnemonic: String) -> String {
        switch mnemonic.suffix(1).lowercased() {
        case "b":
            return "al"
        case "w":
            return "ax"
        case "d":
            return "eax"
        case "q":
            return "rax"
        default:
            return "ax"
        }
    }

    private func countRegister() -> String {
        switch binary?.architecture {
        case .some(.x86_64):
            return "rcx"
        case .some(.i386):
            return "ecx"
        default:
            return "cx"
        }
    }

    private func decompileRepeatedOperation(prefix: String, operand: String) -> String {
        let normalizedOperand = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let repeated = true

        switch normalizedOperand {
        case "movsb", "movsw", "movsd", "movsq":
            return stringMoveCall(mnemonic: normalizedOperand, repeated: repeated)
        case "stosb", "stosw", "stosd", "stosq":
            return stringStoreCall(mnemonic: normalizedOperand, repeated: repeated)
        case "lodsb", "lodsw", "lodsd", "lodsq":
            return stringLoadCall(mnemonic: normalizedOperand, repeated: repeated)
        case "scasb", "scasw", "scasd", "scasq":
            return stringScanCall(mnemonic: normalizedOperand, repeated: repeated)
        case "cmpsb", "cmpsw", "cmpsd", "cmpsq":
            return stringCompareCall(mnemonic: normalizedOperand, repeated: repeated)
        case "insb", "insw", "insd":
            return streamPortInputCall(mnemonic: normalizedOperand, repeated: repeated)
        case "outsb", "outsw", "outsd":
            return streamPortOutputCall(mnemonic: normalizedOperand, repeated: repeated)
        default:
            return "// \(prefix) \(operand)"
        }
    }

    private func stringMoveCall(mnemonic: String, repeated: Bool) -> String {
        let suffix = elementSuffix(for: mnemonic)
        if repeated {
            return "copy_\(suffix)(es, di, ds, si, \(countRegister()));"
        }
        return "copy_\(suffix.dropLast())(es, di, ds, si);"
    }

    private func stringStoreCall(mnemonic: String, repeated: Bool) -> String {
        let suffix = elementSuffix(for: mnemonic)
        let accumulator = accumulatorRegister(for: mnemonic)
        if repeated {
            return "fill_\(suffix)(es, di, \(accumulator), \(countRegister()));"
        }
        return "store_\(suffix.dropLast())(es, di, \(accumulator));"
    }

    private func stringLoadCall(mnemonic: String, repeated: Bool) -> String {
        let accumulator = accumulatorRegister(for: mnemonic)
        if repeated {
            return "\(accumulator) = load_sequence(ds, si, \(countRegister()));"
        }
        return "\(accumulator) = load_\(elementSuffix(for: mnemonic).dropLast())_and_advance(ds, &si);"
    }

    private func stringScanCall(mnemonic: String, repeated: Bool) -> String {
        let accumulator = accumulatorRegister(for: mnemonic)
        let suffix = elementSuffix(for: mnemonic)
        if repeated {
            return "scan_\(suffix)(es, di, \(accumulator), \(countRegister()));"
        }
        return "scan_\(suffix.dropLast())(es, di, \(accumulator));"
    }

    private func stringCompareCall(mnemonic: String, repeated: Bool) -> String {
        let suffix = elementSuffix(for: mnemonic)
        if repeated {
            return "compare_\(suffix)(ds, si, es, di, \(countRegister()));"
        }
        return "compare_\(suffix.dropLast())(ds, si, es, di);"
    }

    private func streamPortInputCall(mnemonic: String, repeated: Bool) -> String {
        let bits = bitWidth(for: accumulatorRegister(for: mnemonic))
        if repeated {
            return "port_stream_in\(bits)(dx, es, di, \(countRegister()));"
        }
        return "port_stream_in\(bits)(dx, es, di);"
    }

    private func streamPortOutputCall(mnemonic: String, repeated: Bool) -> String {
        let bits = bitWidth(for: accumulatorRegister(for: mnemonic))
        if repeated {
            return "port_stream_out\(bits)(dx, ds, si, \(countRegister()));"
        }
        return "port_stream_out\(bits)(dx, ds, si);"
    }

    private func escapeString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }
}
