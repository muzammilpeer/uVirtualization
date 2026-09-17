import Foundation

struct RenameTransaction: Codable {
    var source: String
    var destination: String
}

extension VMStore {
    /// Repair only operations with an explicit journal; never guess at arbitrary directories.
    public func recoverRenames() throws {
        let directory = root.appendingPathComponent(".transactions")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for journal in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where journal.pathExtension == "json" {
            try requireRegularFile(journal)
            let transaction = try JSONDecoder().decode(RenameTransaction.self, from: Data(contentsOf: journal))
            try VMConfiguration.validateName(transaction.source)
            try VMConfiguration.validateName(transaction.destination)
            guard transaction.source != transaction.destination else { throw UVError("Invalid rename journal.") }
            let locks = try [transaction.source, transaction.destination].sorted().map { try lock($0) }
            defer { locks.forEach { $0.unlock() } }
            let source = try self.directory(transaction.source)
            let destination = try self.directory(transaction.destination)
            let hasSource = FileManager.default.fileExists(atPath: source.path)
            let hasDestination = FileManager.default.fileExists(atPath: destination.path)
            guard hasSource != hasDestination else { throw UVError("Ambiguous interrupted rename; preserving both paths and journal at \(journal.path).") }
            let existing = hasSource ? source : destination
            let values = try existing.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw UVError("Unsafe rename recovery path.") }
            let config = existing.appendingPathComponent("config.json")
            try requireRegularFile(config)
            var model = try JSONDecoder().decode(VMConfiguration.self, from: Data(contentsOf: config))
            try model.validate()
            guard [transaction.source, transaction.destination].contains(model.name) else { throw UVError("Rename journal does not match the VM identity.") }
            model.name = hasSource ? transaction.source : transaction.destination
            try save(model, at: existing)
            try FileManager.default.removeItem(at: journal)
        }
    }
}
