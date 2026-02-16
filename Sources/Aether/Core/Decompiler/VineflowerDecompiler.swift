import Foundation
import Darwin

final class VineflowerDecompiler {
    private static let timeoutSeconds: TimeInterval = 20
    private static let staleCleanupGraceSeconds: TimeInterval = 1.5
    private static let processScanTimeoutSeconds: TimeInterval = 2
    private static let decompileLock = NSLock()

    enum VineflowerError: LocalizedError {
        case executableNotFound
        case processFailed(status: Int32, message: String)
        case outputNotFound(String?)
        case sourceReadFailed(URL)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Vineflower executable not found"
            case .processFailed(let status, let message):
                if message.isEmpty {
                    return "Vineflower failed with status \(status)"
                }
                return "Vineflower failed with status \(status): \(message)"
            case .outputNotFound(let className):
                if let className {
                    return "Vineflower output source for class '\(className)' not found"
                }
                return "Vineflower output source not found"
            case .sourceReadFailed(let url):
                return "Failed to read Vineflower output: \(url.path)"
            }
        }
    }

    static func findExecutablePath() -> String? {
        var candidates: [String] = []

        if let brewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !brewPrefix.isEmpty {
            candidates.append("\(brewPrefix)/bin/vineflower")
        }

        candidates.append("/opt/homebrew/bin/vineflower")
        candidates.append("/usr/local/bin/vineflower")

        let fileManager = FileManager.default
        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    func decompile(inputURL: URL, preferredClassName: String?) throws -> String {
        Self.decompileLock.lock()
        defer { Self.decompileLock.unlock() }

        guard let executablePath = Self.findExecutablePath() else {
            throw VineflowerError.executableNotFound
        }

        Self.cleanupStaleAetherVineflowerProcesses()

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether-vineflower-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let logURL = outputDirectory.appendingPathComponent("vineflower.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [inputURL.path, outputDirectory.path]
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning {
                process.interrupt()
            }
            throw VineflowerError.processFailed(
                status: -1,
                message: "Timed out after \(Int(Self.timeoutSeconds)) seconds"
            )
        }

        let processOutput = (try? String(contentsOf: logURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw VineflowerError.processFailed(status: process.terminationStatus, message: processOutput)
        }

        guard let sourceURL = findDecompiledSource(
            in: outputDirectory,
            preferredClassName: preferredClassName
        ) else {
            throw VineflowerError.outputNotFound(preferredClassName)
        }

        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw VineflowerError.sourceReadFailed(sourceURL)
        }

        return source
    }

    private func findDecompiledSource(in outputDirectory: URL, preferredClassName: String?) -> URL? {
        let fileManager = FileManager.default
        let sourceExtensions = Set(["java", "kt"])

        if let preferredClassName {
            let relativeClassPath = preferredClassName.replacingOccurrences(of: ".", with: "/")
            for ext in sourceExtensions {
                let exact = outputDirectory.appendingPathComponent("\(relativeClassPath).\(ext)")
                if fileManager.fileExists(atPath: exact.path) {
                    return exact
                }
            }

            if let outerClass = relativeClassPath.split(separator: "$").first {
                for ext in sourceExtensions {
                    let outerClassURL = outputDirectory.appendingPathComponent("\(outerClass).\(ext)")
                    if fileManager.fileExists(atPath: outerClassURL.path) {
                        return outerClassURL
                    }
                }
            }

            let simpleClassName = preferredClassName.split(separator: ".").last.map(String.init) ?? preferredClassName
            let simpleCandidates = [simpleClassName, simpleClassName.split(separator: "$").first.map(String.init) ?? simpleClassName]
                .flatMap { className in
                    sourceExtensions.map { "\(className).\($0)" }
                }
            if let matched = firstSourceFile(in: outputDirectory, where: { simpleCandidates.contains($0.lastPathComponent) }) {
                return matched
            }
        }

        return firstSourceFile(in: outputDirectory)
    }

    private func firstSourceFile(in directory: URL, where predicate: ((URL) -> Bool)? = nil) -> URL? {
        let fileManager = FileManager.default
        let sourceExtensions = Set(["java", "kt"])
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard sourceExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            if let predicate {
                if predicate(fileURL) {
                    return fileURL
                }
            } else {
                return fileURL
            }
        }

        return nil
    }

    static func cleanupStaleAetherVineflowerProcesses() {
        let stalePIDs = detectStaleAetherVineflowerPIDs()
        guard !stalePIDs.isEmpty else { return }

        for pid in stalePIDs {
            _ = kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(staleCleanupGraceSeconds)
        var remaining = Set(stalePIDs)
        while !remaining.isEmpty && Date() < deadline {
            remaining = Set(remaining.filter { isProcessRunning($0) })
            if !remaining.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        for pid in remaining {
            _ = kill(pid, SIGKILL)
        }
    }

    private static func detectStaleAetherVineflowerPIDs() -> [pid_t] {
        let pgrepProcess = Process()
        pgrepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrepProcess.arguments = ["-f", "java.*-jar.*vineflower\\.jar.*aether-vineflower-"]

        let stdout = Pipe()
        pgrepProcess.standardOutput = stdout
        pgrepProcess.standardError = Pipe()

        do {
            try pgrepProcess.run()
        } catch {
            return []
        }

        let deadline = Date().addingTimeInterval(processScanTimeoutSeconds)
        while pgrepProcess.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if pgrepProcess.isRunning {
            pgrepProcess.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if pgrepProcess.isRunning {
                pgrepProcess.interrupt()
            }
            return []
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        pgrepProcess.waitUntilExit()

        // pgrep exits with 1 if no matches were found.
        guard pgrepProcess.terminationStatus == 0 || pgrepProcess.terminationStatus == 1 else {
            return []
        }

        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return []
        }

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != getpid() }
    }

    private static func isProcessRunning(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
