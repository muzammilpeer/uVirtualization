import Foundation
import Virtualization

extension VMStore {
    public func requireNoSavedState(_ name: String) throws {
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(".states/" + name + ".bin").path) else {
            throw UVError("VM is suspended. Run it and shut it down before changing, cloning, exporting or deleting it.")
        }
    }
    public func configure(_ name: String, cpu: Int? = nil, memory: Int? = nil, disk: Int? = nil,
                          width: Int? = nil, height: Int? = nil) throws {
        let lock = try lock(name); defer { lock.unlock() }
        try requireNoSavedState(name)
        var model = try load(name)
        if let cpu { model.cpuCount = cpu }
        if let memory { model.memoryMiB = memory }
        if let width { model.displayWidth = width }
        if let height { model.displayHeight = height }
        if let disk {
            guard disk >= model.diskGiB else { throw UVError("Disk shrinking is not supported.") }
            model.diskGiB = disk
        }
        try model.validate()
        guard model.cpuCount >= (model.minimumCPUCount ?? 1), model.memoryMiB >= (model.minimumMemoryMiB ?? 4096) else {
            throw UVError("Resources are below the installed guest's minimum requirements.")
        }
        let dir = try directory(name)
        if model.state == "ready", let disk {
            let url = dir.appendingPathComponent("disk.img")
            try requireRegularFile(url)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let current = try handle.seekToEnd()
            let requested = UInt64(disk) * 1_073_741_824
            guard requested >= current else { throw UVError("Requested disk would truncate existing data.") }
            try handle.truncate(atOffset: requested)
        }
        try save(model, at: dir)
    }

    public func delete(_ name: String) throws {
        let lock = try lock(name); defer { lock.unlock() }
        try requireNoSavedState(name)
        _ = try load(name)
        // Move out of the inventory atomically before removing its data.
        let trash = root.appendingPathComponent(".trash/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory(name), to: trash)
        try FileManager.default.removeItem(at: trash)
    }

    public func clone(_ source: String, to destination: String) throws {
        guard source != destination else { throw UVError("Source and destination must differ.") }
        let locks = try [source, destination].sorted().map { try lock($0) }
        defer { locks.forEach { $0.unlock() } }
        try requireNoSavedState(source)
        var model = try load(source)
        let sourceURL = try directory(source)
        let stage = try stage(destination)
        do {
            for file in try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) {
                guard VMArchive.allowedFiles.contains(file.lastPathComponent) else { throw UVError("Unknown VM artifact: \(file.lastPathComponent)") }
                try requireRegularFile(file)
                // Foundation uses clonefile on supporting filesystems, falling back to a copy.
                try FileManager.default.copyItem(at: file, to: stage.appendingPathComponent(file.lastPathComponent))
            }
            model.name = destination
            try renewIdentity(model: &model, directory: stage)
            try save(model, at: stage)
            try publish(stage, name: destination)
        } catch { try? FileManager.default.removeItem(at: stage); throw error }
    }

    public func rename(_ source: String, to destination: String) throws {
        guard source != destination else { throw UVError("Source and destination must differ.") }
        let locks = try [source, destination].sorted().map { try lock($0) }
        defer { locks.forEach { $0.unlock() } }
        try requireNoSavedState(source)
        var model = try load(source)
        let destinationURL = try directory(destination)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { throw UVError("Destination already exists.") }
        let sourceURL = try directory(source)
        model.name = destination
        try save(model, at: sourceURL)
        do { try FileManager.default.moveItem(at: sourceURL, to: destinationURL) }
        catch { model.name = source; try? save(model, at: sourceURL); throw error }
    }
}

public func requireRegularFile(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw UVError("Expected a regular file: \(url.path)") }
}

public func renewIdentity(model: inout VMConfiguration, directory: URL) throws {
    model.macAddress = VZMACAddress.randomLocallyAdministered().string
    #if arch(arm64)
    if model.guest == "macOS", model.state == "ready" {
        try VZMacMachineIdentifier().dataRepresentation.write(to: directory.appendingPathComponent("machine.bin"), options: .atomic)
    }
    #endif
}
