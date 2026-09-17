import Foundation
import CryptoKit

public enum FileDigest {
    public static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Length-delimited archive with a fixed artifact allowlist; never extracts paths from an archive.
public enum VMArchive {
    public static let allowedFiles: Set<String> = ["config.json", "disk.img", "hardware.bin", "machine.bin", "nvram.bin", "efi.bin"]
    private struct Entry: Codable { var name: String; var size: UInt64; var digest: String }
    private struct Header: Codable { var version: Int; var files: [Entry] }
    public static func export(store: VMStore, name: String, to destination: URL) throws {
        let lock = try store.lock(name); defer { lock.unlock() }
        try store.requireNoSavedState(name)
        _ = try store.load(name)
        let directory = try store.directory(name)
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url -> Entry in
                guard allowedFiles.contains(url.lastPathComponent) else { throw UVError("Unexpected VM artifact.") }
                try requireRegularFile(url)
                return Entry(name: url.lastPathComponent, size: UInt64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!), digest: try FileDigest.sha256(url))
            }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".uvm-export-" + UUID().uuidString)
        try SparseDisk.create(at: temporary, bytes: 1)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        let header = try JSONEncoder().encode(Header(version: 1, files: entries))
        try output.write(contentsOf: Data("UVMARCH1\n\(header.count)\n".utf8))
        try output.write(contentsOf: header)
        for entry in entries {
            let input = try FileHandle(forReadingFrom: directory.appendingPathComponent(entry.name))
            defer { try? input.close() }
            while let bytes = try input.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty { try output.write(contentsOf: bytes) }
        }
        try output.synchronize()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    public static func importVM(store: VMStore, from archive: URL, name: String) throws {
        let lock = try store.lock(name); defer { lock.unlock() }
        try requireRegularFile(archive)
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        func line() throws -> String {
            var data = Data()
            while data.count < 32 {
                guard let byte = try input.read(upToCount: 1), byte.count == 1 else { throw UVError("Truncated archive.") }
                if byte[0] == 10 { return String(decoding: data, as: UTF8.self) }
                data.append(byte)
            }
            throw UVError("Invalid archive header.")
        }
        guard try line() == "UVMARCH1", let length = Int(try line()), (1...65536).contains(length),
              let data = try input.read(upToCount: length), data.count == length else { throw UVError("Invalid archive header.") }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.version == 1, !header.files.isEmpty, header.files.count <= allowedFiles.count,
              Set(header.files.map(\.name)).count == header.files.count,
              header.files.allSatisfy({ allowedFiles.contains($0.name) && $0.size <= 1_125_899_906_842_624 }) else { throw UVError("Unsupported archive entries.") }
        let stage = try store.stage(name)
        defer { try? FileManager.default.removeItem(at: stage) }
        for entry in header.files {
            let url = stage.appendingPathComponent(entry.name)
            try SparseDisk.create(at: url, bytes: max(1, entry.size))
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            var remaining = entry.size
            var offset: UInt64 = 0
            var hash = SHA256()
            while remaining > 0 {
                guard let bytes = try input.read(upToCount: Int(min(remaining, 4 * 1024 * 1024))), !bytes.isEmpty else { throw UVError("Truncated archive data.") }
                hash.update(data: bytes)
                offset += UInt64(bytes.count)
                if bytes == Data(count: bytes.count) { try output.seek(toOffset: offset) }
                else { try output.write(contentsOf: bytes) }
                remaining -= UInt64(bytes.count)
            }
            try output.truncate(atOffset: entry.size)
            let digest = "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == entry.digest else { throw UVError("Archive checksum mismatch: \(entry.name)") }
        }
        guard (try input.read(upToCount: 1))?.isEmpty != false else { throw UVError("Unexpected trailing archive data.") }
        var model = try JSONDecoder().decode(VMConfiguration.self, from: Data(contentsOf: stage.appendingPathComponent("config.json")))
        try model.validate()
        if model.state == "ready" {
            let required: Set<String> = model.guest == "macOS" ? ["disk.img", "hardware.bin", "machine.bin", "nvram.bin"] : ["disk.img", "efi.bin"]
            guard required.isSubset(of: Set(header.files.map(\.name))) else { throw UVError("Archive is missing boot artifacts.") }
        }
        model.name = name
        try renewIdentity(model: &model, directory: stage)
        try store.save(model, at: stage)
        try store.publish(stage, name: name)
    }
}
