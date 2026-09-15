import Foundation
import Compression
import CryptoKit
import Virtualization

public struct PulledImage: Codable {
    public var reference: String
    public var digest: String
    public var cacheName: String
}

public enum RegistryImages {
    public static func cacheStore(_ store: VMStore) -> VMStore { VMStore(root: store.root.appendingPathComponent(".cache/images")) }
    public static func pull(_ reference: OCIReference, store: VMStore, progress: @escaping (String) -> Void = { _ in }) async throws -> PulledImage {
        let lock = try FileLock(url: store.root.appendingPathComponent(".cache/ownership.lock"))
        defer { lock.unlock() }
        let registry = RegistryClient(reference: reference)
        let (manifest, digest) = try await registry.manifest()
        let name = String(digest.dropFirst(7))
        let result = PulledImage(reference: reference.description, digest: digest, cacheName: name)
        let cache = cacheStore(store)
        if (try? cache.load(name)) != nil { return result }
        let stage = try cache.stage(name)
        defer { try? FileManager.default.removeItem(at: stage) }
        let blobs = store.root.appendingPathComponent(".cache/blobs")
        let configBlob = try await registry.blob(manifest.config, cache: blobs)
        guard let platform = try JSONSerialization.jsonObject(with: Data(contentsOf: configBlob)) as? [String: Any],
              platform["architecture"] as? String == "arm64", ["darwin", "linux"].contains(platform["os"] as? String ?? "") else { throw UVError("Only ARM64 macOS/Linux VM images are supported.") }
        let isTart = manifest.layers.contains { $0.mediaType == "application/vnd.cirruslabs.tart.config.v1" }
        var diskOffset: UInt64 = 0
        var seen = Set<String>()
        for (index, layer) in manifest.layers.enumerated() {
            try Task.checkCancellation()
            progress("Fetching layer \(index + 1)/\(manifest.layers.count)")
            let blob = try await registry.blob(layer, cache: blobs)
            switch layer.mediaType {
            case "application/vnd.cirruslabs.tart.disk.v2":
                guard isTart, let text = layer.annotations?["org.cirruslabs.tart.uncompressed-size"], let size = UInt64(text), size > 0, size <= 1_073_741_824 else { throw UVError("Missing or invalid Tart layer size.") }
                let url = stage.appendingPathComponent("disk.img")
                if diskOffset == 0 { try SparseDisk.create(at: url, bytes: 1) }
                let hash = try decompress(blob, to: url, offset: diskOffset, expectedSize: size)
                if let expected = layer.annotations?["org.cirruslabs.tart.uncompressed-content-digest"], hash != expected { throw UVError("Uncompressed layer digest mismatch.") }
                diskOffset += size
                guard diskOffset <= 1_099_511_627_776 else { throw UVError("Image exceeds 1 TiB import limit.") }
            case "application/vnd.cirruslabs.tart.config.v1", "application/vnd.cirruslabs.tart.nvram.v1":
                guard isTart else { throw UVError("Mixed image formats.") }
                let filename = layer.mediaType.contains("config") ? "tart.json" : "nvram.bin"
                guard seen.insert(filename).inserted, layer.size <= 16_777_216 else { throw UVError("Duplicate or oversized metadata layer.") }
                try FileManager.default.copyItem(at: blob, to: stage.appendingPathComponent(filename))
            case "application/vnd.uvirtualization.disk.v1":
                guard !isTart, layer.size > 0 else { throw UVError("Invalid native disk layer.") }
                let url = stage.appendingPathComponent("disk.img")
                if diskOffset == 0 { try SparseDisk.create(at: url, bytes: 1) }
                try appendSparse(blob, to: url, offset: diskOffset)
                diskOffset += UInt64(layer.size)
                guard diskOffset <= 1_099_511_627_776 else { throw UVError("Image exceeds 1 TiB import limit.") }
            case "application/vnd.uvirtualization.artifact.v1":
                guard !isTart, let filename = layer.annotations?["org.uvirtualization.filename"], VMArchive.allowedFiles.contains(filename), filename != "disk.img",
                      seen.insert(filename).inserted, layer.size <= 16_777_216 else { throw UVError("Invalid VM artifact.") }
                try FileManager.default.copyItem(at: blob, to: stage.appendingPathComponent(filename))
            default: throw UVError("Unsupported VM layer format: \(layer.mediaType)")
            }
        }
        guard diskOffset > 0 else { throw UVError("Image contains no disk.") }
        var model: VMConfiguration
        if isTart {
            model = try tartConfiguration(at: stage, name: name, diskBytes: diskOffset)
            try FileManager.default.removeItem(at: stage.appendingPathComponent("tart.json"))
        } else { model = try JSONDecoder().decode(VMConfiguration.self, from: Data(contentsOf: stage.appendingPathComponent("config.json"))) }
        model.name = name
        try model.validate()
        guard model.state == "ready" else { throw UVError("Registry VM is not ready.") }
        let required = model.guest == "macOS" ? ["hardware.bin", "machine.bin", "nvram.bin"] : ["efi.bin"]
        for file in required { try requireRegularFile(stage.appendingPathComponent(file)) }
        try cache.save(model, at: stage)
        try cache.publish(stage, name: name)
        return result
    }

    public static func clone(_ reference: OCIReference, store: VMStore, name: String, progress: @escaping (String) -> Void = { _ in }) async throws {
        try VMConfiguration.validateName(name)
        let destinationLock = try store.lock(name)
        defer { destinationLock.unlock() }
        let destination = try store.directory(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw UVError("Destination already exists.") }
        let image = try await pull(reference, store: store, progress: progress)
        let cacheLock = try FileLock(url: store.root.appendingPathComponent(".cache/ownership.lock"))
        defer { cacheLock.unlock() }
        let cache = cacheStore(store)
        let stage = try store.stage(name)
        defer { try? FileManager.default.removeItem(at: stage) }
        var model = try cache.load(image.cacheName)
        for file in try FileManager.default.contentsOfDirectory(at: cache.directory(image.cacheName), includingPropertiesForKeys: nil) {
            try requireRegularFile(file)
            try FileManager.default.copyItem(at: file, to: stage.appendingPathComponent(file.lastPathComponent))
        }
        model.name = name
        try renewIdentity(model: &model, directory: stage)
        try store.save(model, at: stage)
        try store.publish(stage, name: name)
    }

    static func tartConfiguration(at directory: URL, name: String, diskBytes: UInt64) throws -> VMConfiguration {
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("tart.json"))) as? [String: Any],
              json["version"] as? Int == 1, (json["arch"] as? String ?? "arm64") == "arm64",
              (json["diskFormat"] as? String ?? "raw") == "raw",
              let cpu = json["cpuCount"] as? Int, let memory = json["memorySize"] as? UInt64 else { throw UVError("Unsupported Tart configuration.") }
        var model = try VMConfiguration(name: name, cpuCount: cpu, memoryMiB: Int(memory / 1_048_576), diskGiB: Int((diskBytes + 1_073_741_823) / 1_073_741_824))
        model.guest = (json["os"] as? String ?? "darwin") == "linux" ? "linux" : "macOS"
        model.state = "ready"
        model.macAddress = json["macAddress"] as? String
        model.minimumCPUCount = json["cpuCountMin"] as? Int
        if let min = json["memorySizeMin"] as? UInt64 { model.minimumMemoryMiB = Int((min + 1_048_575) / 1_048_576) }
        if let display = json["display"] as? [String: Any], let width = display["width"] as? Int, let height = display["height"] as? Int {
            model.displayWidth = width; model.displayHeight = height
        }
        if model.guest == "macOS" {
            guard let hardwareText = json["hardwareModel"] as? String, let hardware = Data(base64Encoded: hardwareText),
                  let identifierText = json["ecid"] as? String, let identifier = Data(base64Encoded: identifierText) else { throw UVError("Invalid Tart Mac identity.") }
            try hardware.write(to: directory.appendingPathComponent("hardware.bin"))
            try identifier.write(to: directory.appendingPathComponent("machine.bin"))
        } else { try FileManager.default.moveItem(at: directory.appendingPathComponent("nvram.bin"), to: directory.appendingPathComponent("efi.bin")) }
        try model.validate()
        return model
    }

    static func decompress(_ source: URL, to destination: URL, offset: UInt64, expectedSize: UInt64) throws -> String {
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var written: UInt64 = 0
        var hash = SHA256()
        let filter = try OutputFilter(.decompress, using: .lz4, bufferCapacity: 4 * 1024 * 1024) { data in
            guard let data else { return }
            written += UInt64(data.count)
            guard written <= expectedSize else { throw UVError("Decompressed layer exceeds declared size.") }
            hash.update(data: data)
            if data != Data(count: data.count) {
                try output.seek(toOffset: offset + written - UInt64(data.count))
                try output.write(contentsOf: data)
            }
        }
        while let bytes = try input.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty { try filter.write(bytes) }
        try filter.finalize()
        guard written == expectedSize else { throw UVError("Decompressed layer size mismatch.") }
        try output.truncate(atOffset: offset + written)
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func appendSparse(_ source: URL, to destination: URL, offset: UInt64) throws {
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var position = offset
        while let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            if data != Data(count: data.count) { try output.seek(toOffset: position); try output.write(contentsOf: data) }
            position += UInt64(data.count)
        }
        try output.truncate(atOffset: position)
    }
}
