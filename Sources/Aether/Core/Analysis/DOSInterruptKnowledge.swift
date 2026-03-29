import Foundation

struct DOSInterruptCall {
    let interruptVector: UInt8
    let service: UInt16?
    let name: String
    let statement: String
    let wrapperName: String?
}

enum DOSInterruptKnowledge {
    static func analyze(instructions: [Instruction], binary: BinaryFile) -> [UInt64: DOSInterruptCall] {
        guard binary.format == .dos || binary.architecture == .x86_16 else {
            return [:]
        }

        var annotations: [UInt64: DOSInterruptCall] = [:]
        var state = RegisterState()

        for instruction in instructions.sorted(by: { $0.address < $1.address }) {
            if instruction.type == .interrupt, let vector = parseImmediate(instruction.operands).flatMap(UInt8.init(exactly:)) {
                annotations[instruction.address] = classifyInterrupt(vector: vector, state: state)
                continue
            }

            state.apply(instruction)
        }

        return annotations
    }

    static func wrapperName(for instructions: [Instruction], binary: BinaryFile) -> String? {
        guard binary.format == .dos || binary.architecture == .x86_16 else {
            return nil
        }

        let annotations = analyze(instructions: instructions, binary: binary)
        guard annotations.count == 1, let call = annotations.values.first, let wrapperName = call.wrapperName else {
            return nil
        }

        let meaningful = instructions
            .sorted(by: { $0.address < $1.address })
            .filter { !isNoise($0) }

        guard !meaningful.isEmpty, meaningful.count <= 8 else {
            return nil
        }

        let interruptCount = meaningful.filter { $0.type == .interrupt }.count
        guard interruptCount == 1 else {
            return nil
        }

        let isWrapper = meaningful.allSatisfy { instruction in
            if instruction.type == .interrupt || instruction.type == .return {
                return true
            }

            let mnemonic = instruction.mnemonic.lowercased()
            if ["mov", "movzx", "movsx", "lea", "xor", "push", "pop"].contains(mnemonic) {
                return true
            }

            return false
        }

        return isWrapper ? wrapperName : nil
    }

    private static func classifyInterrupt(vector: UInt8, state: RegisterState) -> DOSInterruptCall {
        switch vector {
        case 0x20:
            return DOSInterruptCall(
                interruptVector: vector,
                service: nil,
                name: "dos_terminate",
                statement: "dos_terminate();",
                wrapperName: "dos_terminate"
            )
        case 0x21:
            return classifyDOSInterrupt21(state: state)
        case 0x10:
            return classifyBIOSVideoInterrupt(state: state)
        case 0x16:
            return classifyBIOSKeyboardInterrupt(state: state)
        default:
            return DOSInterruptCall(
                interruptVector: vector,
                service: nil,
                name: String(format: "interrupt_0x%02X", vector),
                statement: String(format: "interrupt_0x%02X();", vector),
                wrapperName: nil
            )
        }
    }

    private static func classifyDOSInterrupt21(state: RegisterState) -> DOSInterruptCall {
        let service = state.immediateValue(of: "ah")
        let pointerDSDX = farPointer(segment: state.expression(for: "ds"), offset: state.expression(for: "dx"))
        let pointerESBX = farPointer(segment: state.expression(for: "es"), offset: state.expression(for: "bx"))
        let pointerESDI = farPointer(segment: state.expression(for: "es"), offset: state.expression(for: "di"))
        let pointerDSSI = farPointer(segment: state.expression(for: "ds"), offset: state.expression(for: "si"))

        guard let service else {
            return DOSInterruptCall(
                interruptVector: 0x21,
                service: nil,
                name: "dos_int21",
                statement: "dos_int21();",
                wrapperName: nil
            )
        }

        switch service {
        case 0x01:
            return call(0x21, service, "dos_read_char_echo", "result = dos_read_char_echo();")
        case 0x02:
            return call(0x21, service, "dos_write_char", "dos_write_char(\(state.expression(for: "dl")));")
        case 0x06:
            return call(0x21, service, "dos_direct_console_io", "result = dos_direct_console_io(\(state.expression(for: "dl")));")
        case 0x07:
            return call(0x21, service, "dos_read_char_no_echo", "result = dos_read_char_no_echo();")
        case 0x08:
            return call(0x21, service, "dos_read_console_char", "result = dos_read_console_char();")
        case 0x09:
            return call(0x21, service, "dos_print_string", "dos_print_string(\(pointerDSDX));")
        case 0x0A:
            return call(0x21, service, "dos_buffered_input", "dos_buffered_input(\(pointerDSDX));")
        case 0x0B:
            return call(0x21, service, "dos_check_stdin_status", "result = dos_check_stdin_status();")
        case 0x0C:
            return call(0x21, service, "dos_flush_stdin", "result = dos_flush_stdin(\(state.expression(for: "al")));")
        case 0x19:
            return call(0x21, service, "dos_get_default_drive", "result = dos_get_default_drive();")
        case 0x1A:
            return call(0x21, service, "dos_set_dta", "dos_set_dta(\(pointerDSDX));")
        case 0x25:
            return call(0x21, service, "dos_set_interrupt_vector", "dos_set_interrupt_vector(\(state.expression(for: "al")), \(pointerDSDX));")
        case 0x2A:
            return call(0x21, service, "dos_get_date", "result = dos_get_date();")
        case 0x2C:
            return call(0x21, service, "dos_get_time", "result = dos_get_time();")
        case 0x30:
            return call(0x21, service, "dos_get_version", "result = dos_get_version();")
        case 0x31:
            return call(0x21, service, "dos_stay_resident", "dos_stay_resident(\(state.expression(for: "al")), \(state.expression(for: "dx")));")
        case 0x35:
            return call(0x21, service, "dos_get_interrupt_vector", "result = dos_get_interrupt_vector(\(state.expression(for: "al")));")
        case 0x39:
            return call(0x21, service, "dos_make_directory", "result = dos_make_directory(\(pointerDSDX));")
        case 0x3A:
            return call(0x21, service, "dos_remove_directory", "result = dos_remove_directory(\(pointerDSDX));")
        case 0x3B:
            return call(0x21, service, "dos_change_directory", "result = dos_change_directory(\(pointerDSDX));")
        case 0x3C:
            return call(0x21, service, "dos_create_file", "result = dos_create_file(\(pointerDSDX), \(state.expression(for: "cx")));")
        case 0x3D:
            return call(0x21, service, "dos_open_file", "result = dos_open_file(\(pointerDSDX), \(fileAccessMode(state.expression(for: "al"), immediate: state.immediateValue(of: "al"))));")
        case 0x3E:
            return call(0x21, service, "dos_close_file", "result = dos_close_file(\(state.expression(for: "bx")));")
        case 0x3F:
            return call(0x21, service, "dos_read_file", "result = dos_read_file(\(state.expression(for: "bx")), \(pointerDSDX), \(state.expression(for: "cx")));")
        case 0x40:
            return call(0x21, service, "dos_write_file", "result = dos_write_file(\(state.expression(for: "bx")), \(pointerDSDX), \(state.expression(for: "cx")));")
        case 0x41:
            return call(0x21, service, "dos_delete_file", "result = dos_delete_file(\(pointerDSDX));")
        case 0x42:
            return call(0x21, service, "dos_seek_file", "result = dos_seek_file(\(state.expression(for: "bx")), \(seekOrigin(state.expression(for: "al"), immediate: state.immediateValue(of: "al"))), \(wideExpression(high: state.expression(for: "cx"), low: state.expression(for: "dx"))));")
        case 0x43:
            return call(0x21, service, "dos_file_attributes", "result = dos_file_attributes(\(state.expression(for: "al")), \(pointerDSDX), \(state.expression(for: "cx")));")
        case 0x44:
            return call(0x21, service, "dos_ioctl", "result = dos_ioctl(\(state.expression(for: "al")), \(state.expression(for: "bx")), \(state.expression(for: "cx")), \(pointerDSDX));")
        case 0x47:
            return call(0x21, service, "dos_get_current_directory", "result = dos_get_current_directory(\(state.expression(for: "dl")), \(pointerDSSI));")
        case 0x48:
            return call(0x21, service, "dos_allocate_memory", "result = dos_allocate_memory(\(state.expression(for: "bx")));")
        case 0x49:
            return call(0x21, service, "dos_free_memory", "result = dos_free_memory(\(state.expression(for: "es")));")
        case 0x4A:
            return call(0x21, service, "dos_resize_memory", "result = dos_resize_memory(\(state.expression(for: "es")), \(state.expression(for: "bx")));")
        case 0x4B:
            return call(0x21, service, "dos_exec", "result = dos_exec(\(execMode(state.expression(for: "al"), immediate: state.immediateValue(of: "al"))), \(pointerDSDX), \(pointerESBX));")
        case 0x4C:
            return call(0x21, service, "dos_exit", "dos_exit(\(state.expression(for: "al")));")
        case 0x4D:
            return call(0x21, service, "dos_get_return_code", "result = dos_get_return_code();")
        case 0x4E:
            return call(0x21, service, "dos_find_first", "result = dos_find_first(\(pointerDSDX), \(state.expression(for: "cx")));")
        case 0x4F:
            return call(0x21, service, "dos_find_next", "result = dos_find_next();")
        case 0x56:
            return call(0x21, service, "dos_rename_file", "result = dos_rename_file(\(pointerDSDX), \(pointerESDI));")
        default:
            return DOSInterruptCall(
                interruptVector: 0x21,
                service: UInt16(service),
                name: String(format: "dos_int21_%02X", service),
                statement: String(format: "dos_int21_0x%02X();", service),
                wrapperName: String(format: "dos_int21_%02X", service)
            )
        }
    }

    private static func classifyBIOSVideoInterrupt(state: RegisterState) -> DOSInterruptCall {
        let service = state.immediateValue(of: "ah")

        switch service {
        case 0x00:
            return call(0x10, service, "bios_set_video_mode", "bios_set_video_mode(\(state.expression(for: "al")));")
        case 0x02:
            return call(0x10, service, "bios_set_cursor_position", "bios_set_cursor_position(\(state.expression(for: "bh")), \(state.expression(for: "dh")), \(state.expression(for: "dl")));")
        case 0x0E:
            return call(0x10, service, "bios_teletype_output", "bios_teletype_output(\(state.expression(for: "al")));")
        default:
            return DOSInterruptCall(
                interruptVector: 0x10,
                service: service.map(UInt16.init),
                name: "bios_video_interrupt",
                statement: "bios_video_interrupt();",
                wrapperName: nil
            )
        }
    }

    private static func classifyBIOSKeyboardInterrupt(state: RegisterState) -> DOSInterruptCall {
        let service = state.immediateValue(of: "ah")

        switch service {
        case 0x00:
            return call(0x16, service, "bios_read_key", "result = bios_read_key();")
        case 0x01:
            return call(0x16, service, "bios_peek_key", "result = bios_peek_key();")
        case 0x02:
            return call(0x16, service, "bios_get_shift_flags", "result = bios_get_shift_flags();")
        default:
            return DOSInterruptCall(
                interruptVector: 0x16,
                service: service.map(UInt16.init),
                name: "bios_keyboard_interrupt",
                statement: "bios_keyboard_interrupt();",
                wrapperName: nil
            )
        }
    }

    private static func call(_ vector: UInt8, _ service: UInt8?, _ name: String, _ statement: String) -> DOSInterruptCall {
        DOSInterruptCall(
            interruptVector: vector,
            service: service.map(UInt16.init),
            name: name,
            statement: statement,
            wrapperName: name
        )
    }

    private static func fileAccessMode(_ expression: String, immediate: UInt8?) -> String {
        switch immediate {
        case 0x00: return ".readOnly"
        case 0x01: return ".writeOnly"
        case 0x02: return ".readWrite"
        default: return expression
        }
    }

    private static func seekOrigin(_ expression: String, immediate: UInt8?) -> String {
        switch immediate {
        case 0x00: return ".fromStart"
        case 0x01: return ".fromCurrent"
        case 0x02: return ".fromEnd"
        default: return expression
        }
    }

    private static func execMode(_ expression: String, immediate: UInt8?) -> String {
        switch immediate {
        case 0x00: return ".loadAndExecute"
        case 0x01: return ".loadButDoNotExecute"
        case 0x03: return ".loadOverlay"
        default: return expression
        }
    }

    private static func farPointer(segment: String, offset: String) -> String {
        "MK_FP(\(segment), \(offset))"
    }

    private static func wideExpression(high: String, low: String) -> String {
        "((\(high) << 16) | \(low))"
    }

    fileprivate static func parseImmediate(_ value: String) -> UInt16? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        if text.hasPrefix("0x") {
            return UInt16(text.dropFirst(2), radix: 16)
        }
        return UInt16(text)
    }

    private static func isNoise(_ instruction: Instruction) -> Bool {
        let mnemonic = instruction.mnemonic.lowercased()
        let operands = instruction.operands.lowercased()

        if instruction.type == .nop {
            return true
        }
        if mnemonic == "push" && operands == "bp" {
            return true
        }
        if mnemonic == "mov" && operands.contains("bp, sp") {
            return true
        }
        if mnemonic == "pop" && operands == "bp" {
            return true
        }
        if mnemonic == "ret" || mnemonic == "retn" {
            return false
        }
        return false
    }
}

private struct RegisterState {
    private var expressions: [String: String] = [:]
    private var immediates: [String: UInt16] = [:]

    mutating func apply(_ instruction: Instruction) {
        let mnemonic = instruction.mnemonic.lowercased()
        let operands = instruction.operands.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        switch mnemonic {
        case "mov", "movzx", "movsx":
            guard operands.count == 2, let destination = canonicalRegister(operands[0]) else { return }
            if let immediate = DOSInterruptKnowledge.parseImmediate(operands[1]) {
                assignImmediate(immediate, to: destination)
            } else {
                assignExpression(normalizedExpression(operands[1]), to: destination)
            }
        case "lea":
            guard operands.count == 2, let destination = canonicalRegister(operands[0]) else { return }
            assignExpression(normalizedExpression(operands[1], stripBrackets: true), to: destination)
        case "xor":
            guard operands.count == 2, let destination = canonicalRegister(operands[0]) else { return }
            let source = canonicalRegister(operands[1])
            if source == destination {
                assignImmediate(0, to: destination)
            } else {
                clear(destination)
            }
        case "add", "sub", "and", "or", "imul", "mul", "idiv", "div", "inc", "dec", "neg", "not", "shl", "shr", "sal", "sar", "pop":
            guard let destination = operands.first.flatMap(canonicalRegister) else { return }
            clear(destination)
        default:
            break
        }
    }

    func expression(for register: String) -> String {
        let canonical = canonicalRegister(register) ?? register.lowercased()
        return expressions[canonical] ?? canonical
    }

    func immediateValue(of register: String) -> UInt8? {
        let canonical = canonicalRegister(register) ?? register.lowercased()
        if let direct = immediates[canonical] {
            return UInt8(truncatingIfNeeded: direct)
        }
        if canonical == "ah", let ax = immediates["ax"] {
            return UInt8((ax >> 8) & 0xFF)
        }
        if canonical == "al", let ax = immediates["ax"] {
            return UInt8(ax & 0xFF)
        }
        return nil
    }

    private mutating func assignImmediate(_ value: UInt16, to register: String) {
        let canonical = canonicalRegister(register) ?? register
        expressions[canonical] = formattedImmediate(value, width: registerWidth(for: canonical))
        immediates[canonical] = value

        switch canonical {
        case "ax", "bx", "cx", "dx":
            let high = highRegister(of: canonical)
            let low = lowRegister(of: canonical)
            let highValue = UInt16((value >> 8) & 0xFF)
            let lowValue = UInt16(value & 0xFF)
            expressions[high] = formattedImmediate(highValue, width: 2)
            expressions[low] = formattedImmediate(lowValue, width: 2)
            immediates[high] = highValue
            immediates[low] = lowValue
        case "ah", "al", "bh", "bl", "ch", "cl", "dh", "dl":
            clear(parentRegister(of: canonical))
            expressions[canonical] = formattedImmediate(value & 0xFF, width: 2)
            immediates[canonical] = value & 0xFF
        default:
            break
        }
    }

    private mutating func assignExpression(_ expression: String, to register: String) {
        let canonical = canonicalRegister(register) ?? register
        expressions[canonical] = expression
        immediates[canonical] = nil

        switch canonical {
        case "ax", "bx", "cx", "dx":
            clear(highRegister(of: canonical))
            clear(lowRegister(of: canonical))
            expressions[canonical] = expression
        case "ah", "al", "bh", "bl", "ch", "cl", "dh", "dl":
            clear(parentRegister(of: canonical))
            expressions[canonical] = expression
        default:
            break
        }
    }

    private mutating func clear(_ register: String?) {
        guard let register else { return }
        let canonical = canonicalRegister(register) ?? register
        expressions[canonical] = nil
        immediates[canonical] = nil

        switch canonical {
        case "ax", "bx", "cx", "dx":
            expressions[highRegister(of: canonical)] = nil
            expressions[lowRegister(of: canonical)] = nil
            immediates[highRegister(of: canonical)] = nil
            immediates[lowRegister(of: canonical)] = nil
        case "ah", "al", "bh", "bl", "ch", "cl", "dh", "dl":
            expressions[parentRegister(of: canonical)] = nil
            immediates[parentRegister(of: canonical)] = nil
        default:
            break
        }
    }

    private func normalizedExpression(_ text: String, stripBrackets: Bool = false) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        if stripBrackets, value.hasPrefix("[") && value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        if let register = canonicalRegister(value) {
            return register
        }
        return value
    }

    private func formattedImmediate(_ value: UInt16, width: Int) -> String {
        switch width {
        case 2:
            return String(format: "0x%02X", value & 0xFF)
        default:
            return String(format: "0x%04X", value)
        }
    }

    private func registerWidth(for register: String) -> Int {
        switch register {
        case "ah", "al", "bh", "bl", "ch", "cl", "dh", "dl":
            return 2
        default:
            return 4
        }
    }

    private func canonicalRegister(_ text: String) -> String? {
        let register = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let known: Set<String> = [
            "ax", "bx", "cx", "dx", "si", "di", "bp", "sp",
            "ds", "es", "cs", "ss",
            "ah", "al", "bh", "bl", "ch", "cl", "dh", "dl"
        ]
        return known.contains(register) ? register : nil
    }

    private func highRegister(of register: String) -> String {
        switch register {
        case "ax": return "ah"
        case "bx": return "bh"
        case "cx": return "ch"
        case "dx": return "dh"
        default: return register
        }
    }

    private func lowRegister(of register: String) -> String {
        switch register {
        case "ax": return "al"
        case "bx": return "bl"
        case "cx": return "cl"
        case "dx": return "dl"
        default: return register
        }
    }

    private func parentRegister(of register: String) -> String {
        switch register {
        case "ah", "al": return "ax"
        case "bh", "bl": return "bx"
        case "ch", "cl": return "cx"
        case "dh", "dl": return "dx"
        default: return register
        }
    }
}
