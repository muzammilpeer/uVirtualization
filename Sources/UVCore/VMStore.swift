import Foundation

/// Shared VM library, configuration and runtime ownership storage.
public struct VMStore {
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root.standardizedFileURL }

    /// A picker may select either the library or a VM bundle inside it.
    public static func resolveSelection(_ url: URL) throws -> (store: VMStore, vmName: String?) {
        let directory = url.standardizedFileURL
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw UVError("Choose a VM library folder or a VM folder, not a file or symbolic link.")
        }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) {
            let store = VMStore(root: directory.deletingLastPathComponent())
            let model = try store.load(directory.lastPathComponent)
            return (store, model.name)
        }
        return (VMStore(root: directory), nil)
    }

    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["UVM_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".uvm", isDirectory: true)
    }

    public func directory(_ name: String) throws -> URL {
        try VMConfiguration.validateName(name)
        return root.appendingPathComponent(name, isDirectory: true)
    }

    public func create(_ configuration: VMConfiguration) throws {
        try configuration.validate()
        let lock = try lock(configuration.name)
        defer { lock.unlock() }
        let destination = try directory(configuration.name)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Exclusive directory creation arbitrates concurrent attempts for the same name.
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            throw UVError("Cannot create '\(configuration.name)'; the name may already exist: \(error.localizedDescription)")
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: destination.appendingPathComponent("config.json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    public func lock(_ name: String) throws -> FileLock {
        try VMConfiguration.validateName(name)
        return try FileLock(url: root.appendingPathComponent(".locks/" + name))
    }

    public func save(_ configuration: VMConfiguration, at directory: URL) throws {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: directory.appendingPathComponent("config.json"), options: .atomic)
    }

    public func stage(_ name: String) throws -> URL {
        let destination = try directory(name)
        guard !fm.fileExists(atPath: destination.path) else { throw UVError("VM '\(name)' already exists.") }
        let stage = root.appendingPathComponent(".staging/\(name)-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return stage
    }

    public func publish(_ stage: URL, name: String) throws {
        try fm.moveItem(at: stage, to: directory(name))
    }

    public func load(_ name: String) throws -> VMConfiguration {
        let directory = try directory(name)
        let file = directory.appendingPathComponent("config.json")
        for url in [directory, file] {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw UVError("Refusing symbolic link: \(url.path)") }
        }
        let configuration = try JSONDecoder().decode(VMConfiguration.self, from: Data(contentsOf: file))
        try configuration.validate()
        guard configuration.name == name else { throw UVError("Configuration name does not match its directory.") }
        return configuration
    }

    public func list() throws -> [VMConfiguration] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        try recoverRenames()
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .filter { url in
                guard !url.lastPathComponent.hasPrefix(".") else { return false }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true || values.isSymbolicLink == true else { return false }
                return fm.fileExists(atPath: url.appendingPathComponent("config.json").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try load($0.lastPathComponent) }
    }
}
