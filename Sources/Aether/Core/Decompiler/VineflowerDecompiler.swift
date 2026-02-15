import Foundation

final class VineflowerDecompiler {
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
        guard let executablePath = Self.findExecutablePath() else {
            throw VineflowerError.executableNotFound
        }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether-vineflower-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [inputURL.path, outputDirectory.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
        let processOutput = [stderrString, stdoutString]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
}
