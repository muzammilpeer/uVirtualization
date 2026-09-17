import Foundation
import CryptoKit
import UVCore
import Darwin

public struct ExecutorConfiguration: Codable {
    public var runnerID: String
    public var uvmPath: String
    public var storePath: String
    public var image: String
    public var ssh: GuestSSH
    public var readinessURLs: [String]
    public var readinessTimeout: Double
    public var buildsDirectory: String
    public var cacheDirectory: String
    public var stageTimeout: Double

    public func validate() throws {
        try VMConfiguration.validateName(runnerID)
        guard uvmPath.hasPrefix("/"), storePath.hasPrefix("/"),
              [uvmPath, storePath, buildsDirectory, cacheDirectory].allSatisfy({ !$0.contains(where: { $0.isNewline || $0 == "\0" }) }),
              buildsDirectory.hasPrefix("/"), cacheDirectory.hasPrefix("/"),
              (5...3600).contains(readinessTimeout), (1...86400).contains(stageTimeout), !image.isEmpty else { throw UVError("Invalid executor paths or deadlines.") }
        if image.contains("/") { _ = try OCIReference(image) } else { try VMConfiguration.validateName(image) }
        try ssh.validate()
        try GuestReadiness.validateEndpoints(readinessURLs)
    }
    public static func load(_ path: String) throws -> Self {
        let url = URL(fileURLWithPath: path)
        try requireRegularFile(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else {
            throw UVError("Executor configuration must be owned by the runner user and not writable by other users.")
        }
        let config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }
    public func jobName(response: Data) throws -> String {
        struct Job: Decodable { let id: Int64 }
        let job = try JSONDecoder().decode(Job.self, from: response)
        guard job.id > 0 else { throw UVError("Invalid trusted GitLab job ID.") }
        let hash = SHA256.hash(data: Data((runnerID + ":" + String(job.id)).utf8)).map { String(format: "%02x", $0) }.joined()
        return "ci-" + String(hash.prefix(40))
    }
    public func identity() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return FileDigest.sha256(try encoder.encode(self))
    }
}

public struct ExecutorJobState: Codable {
    public var name: String
    public var configurationIdentity: String
    public var phase: String
}

public enum ExecutorFailure: Error {
    case build(Int32)
    case infrastructure
}

public enum ExecutorContract {
    public static func failureCode(build: Bool, environment: [String: String]) -> Int32 {
        let key = build ? "BUILD_FAILURE_EXIT_CODE" : "SYSTEM_FAILURE_EXIT_CODE"
        guard let text = environment[key], let value = Int32(text), (1...255).contains(value) else { return build ? 1 : 2 }
        return value
    }
    public static func needsNetwork(_ stage: String) -> Bool {
        stage == "get_sources" || stage == "restore_cache" || stage == "download_artifacts" || stage.hasPrefix("archive_cache") || stage.hasPrefix("upload_artifacts")
    }
}
