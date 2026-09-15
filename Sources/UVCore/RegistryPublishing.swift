import Foundation
import Compression

extension RegistryImages {
    public static func push(store: VMStore, name: String, reference: OCIReference, progress: @escaping (String) -> Void = { _ in }) async throws {
        let lock = try store.lock(name); defer { lock.unlock() }
        let model = try store.load(name)
        guard model.state == "ready" else { throw UVError("Only installed VMs can be published.") }
        let directory = try store.directory(name)
        let temporary = store.root.appendingPathComponent(".uploads/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let client = RegistryClient(reference: reference, pushAccess: true)
        let configURL = temporary.appendingPathComponent("oci.json")
        try JSONSerialization.data(withJSONObject: ["architecture": "arm64", "os": model.guest == "macOS" ? "darwin" : "linux"])
            .write(to: configURL)
        let config = try await client.pushBlob(configURL, mediaType: "application/vnd.oci.image.config.v1+json")
        var layers: [OCIDescriptor] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            guard VMArchive.allowedFiles.contains(file.lastPathComponent) else { throw UVError("Unexpected VM artifact.") }
            try requireRegularFile(file)
            if file.lastPathComponent == "disk.img" {
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                var index = 0
                while let data = try input.read(upToCount: 67_108_864), !data.isEmpty {
                    try Task.checkCancellation()
                    index += 1
                    progress("Uploading disk chunk \(index)")
                    let chunk = temporary.appendingPathComponent("chunk")
                    try ((data as NSData).compressed(using: .lz4) as Data).write(to: chunk, options: .atomic)
                    layers.append(try await client.pushBlob(chunk, mediaType: "application/vnd.uvirtualization.disk.v2", annotations: ["org.uvirtualization.uncompressed-size": String(data.count), "org.uvirtualization.uncompressed-digest": FileDigest.sha256(data)]))
                }
            } else {
                progress("Uploading \(file.lastPathComponent)")
                layers.append(try await client.pushBlob(file, mediaType: "application/vnd.uvirtualization.artifact.v1", annotations: ["org.uvirtualization.filename": file.lastPathComponent]))
            }
        }
        let manifest = OCIManifest(config: config, layers: layers)
        try manifest.validate()
        try await client.pushManifest(manifest)
        progress("Published \(reference.description)")
    }
    public static func prune(store: VMStore) throws {
        let lock = try FileLock(url: store.root.appendingPathComponent(".cache/ownership.lock"))
        defer { lock.unlock() }
        for component in ["blobs", "images"] {
            let url = store.root.appendingPathComponent(".cache/" + component)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
