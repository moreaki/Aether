import Foundation

/// Legacy DOS MZ executable loader.
/// This maps the load module as a single executable segment so plain DOS executables can be inspected.
final class DOSLoader: BinaryLoaderProtocol {
    private let MZ_MAGIC: UInt16 = 0x5A4D
    private let PE_SIGNATURE: UInt32 = 0x00004550
    private let legacyExecutableSignatures: Set<String> = ["NE", "LE", "LX"]

    func canLoad(data: Data) -> Bool {
        guard data.readUInt16LE(at: 0) == MZ_MAGIC else { return false }
        return resolvePEHeaderOffset(in: data) == nil
    }

    func load(from url: URL, data: Data) throws -> BinaryFile {
        guard data.readUInt16LE(at: 0) == MZ_MAGIC else {
            throw BinaryLoaderError.invalidHeader
        }

        if let signature = detectExtendedExecutableSignature(in: data) {
            throw BinaryLoaderError.unsupportedFormatReason(
                "unsupported \(signature) executable; plain DOS MZ and PE/COFF executables are supported"
            )
        }

        guard let pageCount = data.readUInt16LE(at: 0x04),
              let lastPageBytes = data.readUInt16LE(at: 0x02),
              let relocationCount = data.readUInt16LE(at: 0x06),
              let headerParagraphs = data.readUInt16LE(at: 0x08),
              let entryIP = data.readUInt16LE(at: 0x14),
              let entryCS = data.readUInt16LE(at: 0x16),
              let relocationTableOffset = data.readUInt16LE(at: 0x18) else {
            throw BinaryLoaderError.invalidHeader
        }

        let headerSize = Int(headerParagraphs) * 16
        guard headerSize >= 28, headerSize <= data.count else {
            throw BinaryLoaderError.corruptedFile("Invalid DOS header size: \(headerSize)")
        }

        let declaredFileSize: Int
        if pageCount == 0 {
            declaredFileSize = data.count
        } else {
            declaredFileSize = Int(pageCount - 1) * 512 + (lastPageBytes == 0 ? 512 : Int(lastPageBytes))
        }

        let fileSize = min(max(declaredFileSize, headerSize), data.count)
        let loadModuleOffset = headerSize
        let loadModuleSize = max(fileSize - loadModuleOffset, 0)
        guard loadModuleSize > 0,
              let loadModule = data.subdata(offset: loadModuleOffset, count: loadModuleSize) else {
            throw BinaryLoaderError.corruptedFile("DOS executable has no load module")
        }

        let relocationBytes = Int(relocationCount) * 4
        guard Int(relocationTableOffset) + relocationBytes <= headerSize else {
            throw BinaryLoaderError.corruptedFile("Invalid relocation table")
        }

        let entryPoint = UInt64(entryCS) * 16 + UInt64(entryIP)
        let loadModuleEnd = UInt64(loadModuleSize)
        let mappedEntryPoint = entryPoint < loadModuleEnd ? entryPoint : 0

        let segment = Segment(
            name: "DOS",
            address: 0,
            size: UInt64(loadModuleSize),
            fileOffset: UInt64(loadModuleOffset),
            fileSize: UInt64(loadModuleSize),
            maxProtection: 7,
            initProtection: 7
        )

        let section = Section(
            name: ".load",
            segmentName: "DOS",
            address: 0,
            size: UInt64(loadModuleSize),
            offset: UInt32(loadModuleOffset),
            alignment: 16,
            flags: 0xE0000020,
            data: loadModule
        )

        var symbols: [Symbol] = []
        if entryPoint < loadModuleEnd {
            symbols.append(Symbol(
                name: "start",
                address: entryPoint,
                size: 0,
                type: .function,
                binding: .global,
                section: ".load"
            ))
        }

        return BinaryFile(
            url: url,
            format: .dos,
            architecture: .i386,
            endianness: .little,
            is64Bit: false,
            fileSize: data.count,
            entryPoint: mappedEntryPoint,
            baseAddress: 0,
            sections: [section],
            segments: [segment],
            symbols: symbols,
            data: data
        )
    }

    private func resolvePEHeaderOffset(in data: Data) -> UInt32? {
        let candidates = [
            data.readUInt32LE(at: 0x3C),
            data.readUInt32BE(at: 0x3C)
        ].compactMap { $0 }

        for candidate in candidates {
            guard candidate < UInt32(data.count),
                  Int(candidate) + 4 <= data.count,
                  data.readUInt32LE(at: Int(candidate)) == PE_SIGNATURE else {
                continue
            }
            return candidate
        }

        return nil
    }

    private func detectExtendedExecutableSignature(in data: Data) -> String? {
        let candidates = [
            data.readUInt32LE(at: 0x3C),
            data.readUInt32BE(at: 0x3C)
        ].compactMap { $0 }

        for candidate in candidates {
            guard candidate < UInt32(data.count),
                  Int(candidate) + 2 <= data.count,
                  let signatureData = data.subdata(offset: Int(candidate), count: 2),
                  let signature = String(data: signatureData, encoding: .ascii) else {
                continue
            }

            if legacyExecutableSignatures.contains(signature) {
                return signature
            }
        }

        return nil
    }
}
