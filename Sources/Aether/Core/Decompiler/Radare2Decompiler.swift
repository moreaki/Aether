import Foundation

final class Radare2Decompiler {
    private static let timeoutSeconds: TimeInterval = 10

    enum Radare2Error: LocalizedError {
        case executableNotFound
        case processFailed(status: Int32, message: String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "radare2 executable not found"
            case .processFailed(let status, let message):
                if message.isEmpty {
                    return "radare2 failed with status \(status)"
                }
                return "radare2 failed with status \(status): \(message)"
            case .emptyOutput:
                return "radare2 produced no pseudocode output"
            }
        }
    }

    static func findExecutablePath() -> String? {
        var candidates: [String] = []

        if let brewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !brewPrefix.isEmpty {
            candidates.append("\(brewPrefix)/bin/radare2")
            candidates.append("\(brewPrefix)/bin/r2")
        }

        candidates.append("/opt/homebrew/bin/radare2")
        candidates.append("/opt/homebrew/bin/r2")
        candidates.append("/usr/local/bin/radare2")
        candidates.append("/usr/local/bin/r2")

        let fileManager = FileManager.default
        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    func decompile(function: Function, binary: BinaryFile) throws -> String {
        guard let executablePath = Self.findExecutablePath() else {
            throw Radare2Error.executableNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "-q",
            "-c",
            command(for: function, binary: binary),
            binary.url.path
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.interrupt()
            }
            throw Radare2Error.processFailed(
                status: -1,
                message: "Timed out after \(Int(Self.timeoutSeconds)) seconds"
            )
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw Radare2Error.processFailed(status: process.terminationStatus, message: errorOutput)
        }
        guard !output.isEmpty else {
            throw Radare2Error.emptyOutput
        }

        var result = "// Backend: radare2\n"
        result += "// Source: \(binary.url.lastPathComponent)\n"
        result += String(format: "// Function: 0x%llX (%@)\n\n", function.startAddress, function.displayName)
        result += output
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private func command(for function: Function, binary: BinaryFile) -> String {
        let address = String(format: "0x%llX", function.startAddress)
        let commands = [
            "e scr.color=false",
            "e scr.interactive=false",
            "e asm.arch=\(asmArchitecture(for: binary.architecture))",
            "e asm.bits=\(asmBits(for: binary.architecture))",
            "aaa",
            "af @ \(address)",
            "s \(address)",
            "pdc"
        ]
        return commands.joined(separator: "; ")
    }

    private func asmArchitecture(for architecture: Architecture) -> String {
        switch architecture {
        case .x86_16, .i386, .x86_64:
            return "x86"
        case .arm64, .arm64e:
            return "arm"
        case .armv7:
            return "arm"
        default:
            return "x86"
        }
    }

    private func asmBits(for architecture: Architecture) -> Int {
        switch architecture {
        case .x86_16:
            return 16
        case .i386, .armv7:
            return 32
        case .x86_64, .arm64, .arm64e:
            return 64
        default:
            return max(architecture.pointerSize * 8, 16)
        }
    }
}
