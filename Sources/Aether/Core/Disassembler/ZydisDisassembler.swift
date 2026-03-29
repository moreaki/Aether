import CZydis
import Foundation

struct ZydisDisassembler {
    func disassemble(data: Data, address: UInt64, architecture: Architecture) -> [Instruction] {
        guard let machineMode = machineMode(for: architecture) else {
            return []
        }

        let bytes = [UInt8](data)
        guard !bytes.isEmpty else {
            return []
        }

        var instructions: [Instruction] = []
        instructions.reserveCapacity(min(max(bytes.count / 2, 1), 4096))

        var offset = 0
        var runtimeAddress = address

        while offset < bytes.count {
            var decoded = AetherZydisInstruction()
            let didDecode = bytes.withUnsafeBufferPointer { buffer -> Bool in
                guard let baseAddress = buffer.baseAddress else {
                    return false
                }
                return AetherZydisDecodeInstruction(
                    baseAddress.advanced(by: offset),
                    bytes.count - offset,
                    runtimeAddress,
                    machineMode,
                    &decoded
                ) != 0
            }

            if !didDecode || decoded.length == 0 {
                instructions.append(Instruction(
                    address: runtimeAddress,
                    size: 1,
                    bytes: [bytes[offset]],
                    mnemonic: "db",
                    operands: String(format: "0x%02X", bytes[offset]),
                    architecture: architecture,
                    type: .other
                ))
                offset += 1
                runtimeAddress += 1
                continue
            }

            let size = min(Int(decoded.length), bytes.count - offset)
            var mnemonicBuffer = decoded.mnemonic
            var operandsBuffer = decoded.operands
            let mnemonic = string(from: &mnemonicBuffer)
            let operands = string(from: &operandsBuffer)
            let kind = instructionType(from: decoded.kind, mnemonic: mnemonic)
            let branchTarget = decoded.has_branch_target != 0 ? decoded.branch_target : nil

            instructions.append(Instruction(
                address: runtimeAddress,
                size: size,
                bytes: Array(bytes[offset..<(offset + size)]),
                mnemonic: mnemonic,
                operands: operands,
                architecture: architecture,
                type: kind,
                branchTarget: branchTarget
            ))

            offset += size
            runtimeAddress += UInt64(size)
        }

        return instructions
    }

    private func machineMode(for architecture: Architecture) -> AetherZydisMachineMode? {
        switch architecture {
        case .x86_16:
            return AETHER_ZYDIS_MACHINE_MODE_X86_16
        case .i386:
            return AETHER_ZYDIS_MACHINE_MODE_X86_32
        case .x86_64:
            return AETHER_ZYDIS_MACHINE_MODE_X86_64
        default:
            return nil
        }
    }

    private func instructionType(
        from kind: AetherZydisInstructionKind,
        mnemonic: String
    ) -> InstructionType {
        switch kind {
        case AETHER_ZYDIS_KIND_JUMP:
            return .jump
        case AETHER_ZYDIS_KIND_CONDITIONAL_JUMP:
            return .conditionalJump
        case AETHER_ZYDIS_KIND_CALL:
            return .call
        case AETHER_ZYDIS_KIND_RETURN:
            return .return
        case AETHER_ZYDIS_KIND_PUSH:
            return .push
        case AETHER_ZYDIS_KIND_POP:
            return .pop
        case AETHER_ZYDIS_KIND_NOP:
            return .nop
        case AETHER_ZYDIS_KIND_INTERRUPT:
            return .interrupt
        case AETHER_ZYDIS_KIND_SYSCALL:
            return .syscall
        default:
            return classifyNonControlFlowMnemonic(mnemonic)
        }
    }

    private func classifyNonControlFlowMnemonic(_ mnemonic: String) -> InstructionType {
        let lower = mnemonic.lowercased()

        if lower.hasPrefix("mov") || lower == "lea" || lower == "xchg" {
            return .move
        }
        if lower == "cmp" || lower == "test" {
            return .compare
        }
        if lower == "and" || lower == "or" || lower == "xor" || lower == "not" {
            return .logic
        }
        if lower == "add" || lower == "sub" || lower == "adc" || lower == "sbb" ||
            lower == "mul" || lower == "imul" || lower == "div" || lower == "idiv" ||
            lower == "inc" || lower == "dec" || lower == "neg" ||
            lower == "shl" || lower == "shr" || lower == "sar" || lower == "sal" ||
            lower == "rol" || lower == "ror" || lower == "rcl" || lower == "rcr" {
            return .arithmetic
        }

        return .other
    }

    private func string<T>(from tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { rawBuffer in
            let cString = rawBuffer.bindMemory(to: CChar.self)
            return String(cString: cString.baseAddress!)
        }
    }
}
