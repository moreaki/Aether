import Foundation

struct RBILInterruptReferenceCatalog: Decodable {
    let version: Int
    let release: String
    let sources: [RBILInterruptReferenceSource]
    let entries: [RBILInterruptReferenceEntry]
}

struct RBILInterruptReferenceSource: Decodable {
    let id: String
    let title: String
    let url: String
}

struct RBILInterruptReferenceSelector: Decodable {
    let register: String
    let value: UInt16
    let text: String
}

struct RBILInterruptReferenceEntry: Decodable {
    let lookupKey: String
    let vector: UInt8
    let category: String?
    let header: String
    let selector: String?
    let selectors: [RBILInterruptReferenceSelector]
    let primaryServiceRegister: String?
    let primaryService: UInt16?
    let summary: String?
    let returns: String?
    let notes: [String]
    let seeAlso: [String]
    let sourceFile: String
    let sourceLine: Int
}

enum RBILInterruptReferenceStore {
    private static let catalog: RBILInterruptReferenceCatalog? = loadCatalog()
    private static let entriesByVector: [UInt8: [RBILInterruptReferenceEntry]] = {
        guard let catalog else { return [:] }
        return Dictionary(grouping: catalog.entries, by: \.vector)
    }()

    static func bestMatch(vector: UInt8, service: UInt16?) -> RBILInterruptReferenceEntry? {
        guard let candidates = entriesByVector[vector], !candidates.isEmpty else {
            return nil
        }

        guard let service else {
            let unqualified = candidates.filter { $0.selectors.isEmpty }
            guard !unqualified.isEmpty else {
                return nil
            }
            return bestRankedEntry(in: unqualified)
        }

        let exactMatches = candidates.filter { $0.primaryService == service }
        if let best = bestRankedEntry(in: exactMatches) {
            return best
        }

        return bestRankedEntry(in: candidates)
    }

    static func summary(vector: UInt8, service: UInt16?) -> String? {
        bestMatch(vector: vector, service: service)?.summary
    }

    static func detail(vector: UInt8, service: UInt16?) -> String? {
        guard let entry = bestMatch(vector: vector, service: service) else {
            return nil
        }

        var lines: [String] = [entry.lookupKey, entry.header]
        if let summary = entry.summary, !summary.isEmpty {
            lines.append("")
            lines.append(summary)
        }
        if let returns = entry.returns, !returns.isEmpty {
            lines.append("")
            lines.append("Returns: \(returns)")
        }
        if !entry.notes.isEmpty {
            lines.append("")
            lines.append("Notes:")
            lines.append(contentsOf: entry.notes.map { "- \($0)" })
        }
        if !entry.seeAlso.isEmpty {
            lines.append("")
            lines.append("See Also: \(entry.seeAlso.joined(separator: ", "))")
        }

        let sourceMap = Dictionary(uniqueKeysWithValues: (catalog?.sources ?? []).map { ($0.id, $0) })
        if let localSource = sourceMap["rbil_release_61"] {
            lines.append("")
            lines.append("Source: \(entry.sourceFile):\(entry.sourceLine)")
            lines.append(localSource.title)
            lines.append(localSource.url)
        }

        return lines.joined(separator: "\n")
    }

    private static func bestRankedEntry(in entries: [RBILInterruptReferenceEntry]) -> RBILInterruptReferenceEntry? {
        entries.min { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private static func score(_ entry: RBILInterruptReferenceEntry) -> (Int, Int, String, Int) {
        let servicePriority: Int
        switch entry.primaryServiceRegister?.uppercased() {
        case "AX":
            servicePriority = 0
        case "AH":
            servicePriority = 1
        default:
            servicePriority = 2
        }
        return (entry.selectors.count, servicePriority, entry.sourceFile, entry.sourceLine)
    }

    private static func loadCatalog() -> RBILInterruptReferenceCatalog? {
        guard let url = resourceURL(named: "rbil_interrupt_reference", withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(RBILInterruptReferenceCatalog.self, from: data)
    }

    private static func resourceURL(named name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Reference") {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
