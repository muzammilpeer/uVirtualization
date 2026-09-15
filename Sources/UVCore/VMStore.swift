import Foundation

/// Draft-only store. Boot artifacts and runtime ownership are introduced separately.
public struct VMStore {
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root.standardizedFileURL }

    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["UVM_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".uvm", isDirectory: true)
    }

    private func directory(_ name: String) throws -> URL {
        try VMConfiguration.validateName(name)
        return root.appendingPathComponent(name, isDirectory: true)
    }

    public func create(_ configuration: VMConfiguration) throws {
        try configuration.validate()
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
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try load($0.lastPathComponent) }
    }
}
