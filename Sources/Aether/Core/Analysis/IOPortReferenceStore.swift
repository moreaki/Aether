import Foundation

struct IOPortReferenceCatalog: Decodable {
    let version: Int
    let sources: [IOPortReferenceSource]
    let ports: [IOPortReferenceEntry]
}

struct IOPortReferenceSource: Decodable {
    let id: String
    let title: String
    let url: String
}

struct IOPortReferenceEntry: Decodable {
    let port: UInt16
    let name: String
    let summary: String
    let sourceIDs: [String]
}

enum IOPortReferenceStore {
    private static let catalog: IOPortReferenceCatalog? = loadCatalog()
    private static let portsByNumber: [UInt16: IOPortReferenceEntry] = {
        guard let catalog else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.ports.map { ($0.port, $0) })
    }()
    private static let portsByName: [String: IOPortReferenceEntry] = {
        guard let catalog else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.ports.map { ($0.name, $0) })
    }()

    static func entry(port: UInt16) -> IOPortReferenceEntry? {
        portsByNumber[port]
    }

    static func detail(forPort port: UInt16) -> String? {
        guard let entry = entry(port: port) else {
            return nil
        }

        return detail(for: entry)
    }

    static func detail(forPortNamed name: String) -> String? {
        guard let entry = portsByName[name] else {
            return nil
        }

        return detail(for: entry)
    }

    private static func detail(for entry: IOPortReferenceEntry) -> String {
        let heading = String(format: "%@ (0x%X)", entry.name, entry.port)

        let sourceMap = Dictionary(uniqueKeysWithValues: (catalog?.sources ?? []).map { ($0.id, $0) })
        let sources = entry.sourceIDs.compactMap { sourceMap[$0] }
        guard !sources.isEmpty else {
            return "\(heading)\n\n\(entry.summary)"
        }

        let sourceLines = sources.map { "\($0.title)\n\($0.url)" }.joined(separator: "\n\n")
        return "\(heading)\n\n\(entry.summary)\n\nSources:\n\(sourceLines)"
    }

    private static func loadCatalog() -> IOPortReferenceCatalog? {
        guard let url = resourceURL(named: "io_port_reference", withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(IOPortReferenceCatalog.self, from: data)
    }

    private static func resourceURL(named name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Reference") {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
