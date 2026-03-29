import Foundation

struct DOSInterruptReferenceCatalog: Decodable {
    let version: Int
    let sources: [DOSInterruptReferenceSource]
    let entries: [DOSInterruptReferenceEntry]
}

struct DOSInterruptReferenceSource: Decodable {
    let id: String
    let title: String
    let url: String
}

struct DOSInterruptReferenceEntry: Decodable {
    let vector: UInt8
    let service: UInt16?
    let name: String
    let wrapperName: String?
    let summary: String
    let sourceIDs: [String]
}

enum DOSInterruptReferenceStore {
    private static let catalog: DOSInterruptReferenceCatalog? = loadCatalog()
    private static let entriesByKey: [String: DOSInterruptReferenceEntry] = {
        guard let catalog else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.entries.map { (key(for: $0.vector, service: $0.service), $0) })
    }()
    private static let entriesByName: [String: DOSInterruptReferenceEntry] = {
        guard let catalog else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.name, $0) })
    }()

    static func entry(vector: UInt8, service: UInt16?, fallbackName: String? = nil) -> DOSInterruptReferenceEntry? {
        if let direct = entriesByKey[key(for: vector, service: service)] {
            return direct
        }
        if let fallbackName {
            return entriesByName[fallbackName]
        }
        return nil
    }

    static func entry(named name: String) -> DOSInterruptReferenceEntry? {
        entriesByName[name]
    }

    static func summary(forHelperName name: String) -> String? {
        entriesByName[name]?.summary
    }

    static func summary(vector: UInt8, service: UInt16?, fallbackName: String? = nil) -> String? {
        if let direct = entry(vector: vector, service: service, fallbackName: fallbackName) {
            return direct.summary
        }
        return RBILInterruptReferenceStore.summary(vector: vector, service: service)
    }

    static func detail(vector: UInt8, service: UInt16?) -> String? {
        RBILInterruptReferenceStore.detail(vector: vector, service: service)
    }

    static func detail(forHelperName name: String) -> String? {
        guard let entry = entriesByName[name] else {
            return nil
        }

        let heading = lookupKey(for: entry.vector, service: entry.service)
        let sources = sourceSummaries(for: entry)
        guard !sources.isEmpty else {
            return "\(heading)\n\n\(entry.summary)"
        }

        let sourceLines = sources.map { "\($0.title)\n\($0.url)" }.joined(separator: "\n\n")
        return "\(heading)\n\n\(entry.summary)\n\nSources:\n\(sourceLines)"
    }

    static func sourceSummaries(for entry: DOSInterruptReferenceEntry) -> [DOSInterruptReferenceSource] {
        let sourceMap = Dictionary(uniqueKeysWithValues: (catalog?.sources ?? []).map { ($0.id, $0) })
        return entry.sourceIDs.compactMap { sourceMap[$0] }
    }

    private static func key(for vector: UInt8, service: UInt16?) -> String {
        if let service {
            return "\(vector):\(service)"
        }
        return "\(vector)"
    }

    private static func lookupKey(for vector: UInt8, service: UInt16?) -> String {
        if let service {
            return String(format: "INT %02Xh/AH=%02Xh", vector, service)
        }
        return String(format: "INT %02Xh", vector)
    }

    private static func loadCatalog() -> DOSInterruptReferenceCatalog? {
        guard let url = resourceURL(named: "dos_interrupt_reference", withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(DOSInterruptReferenceCatalog.self, from: data)
    }

    private static func resourceURL(named name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Reference") {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
