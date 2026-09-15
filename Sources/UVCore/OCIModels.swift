import Foundation

public struct OCIReference: Equatable {
    public let host: String
    public let repository: String
    public let reference: String
    public var description: String { host + "/" + repository + (reference.hasPrefix("sha256:") ? "@" : ":") + reference }
    public init(_ text: String) throws {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].range(of: "^[a-zA-Z0-9][a-zA-Z0-9.-]*(?::[0-9]{1,5})?$", options: .regularExpression) != nil else { throw UVError("Registry reference must be HOST/REPOSITORY[:TAG|@sha256:DIGEST].") }
        host = parts[0].lowercased()
        let image = parts[1]
        if image.contains("@") {
            let pair = image.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2, Self.validDigest(pair[1]) else { throw UVError("Invalid image digest.") }
            repository = pair[0]; reference = pair[1]
        } else if let colon = image.lastIndex(of: ":") {
            repository = String(image[..<colon]); reference = String(image[image.index(after: colon)...])
        } else { repository = image; reference = "latest" }
        guard repository.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
            $0.range(of: "^[a-z0-9]+(?:[._-][a-z0-9]+)*$", options: .regularExpression) != nil
        }), !repository.isEmpty,
        reference.hasPrefix("sha256:") || reference.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", options: .regularExpression) != nil else { throw UVError("Invalid repository or tag.") }
    }
    public static func validDigest(_ text: String) -> Bool {
        text.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil
    }
    public func url(_ path: String) -> URL { URL(string: "https://\(host)/v2/\(repository)/\(path)")! }
}

public struct OCIDescriptor: Codable {
    public var mediaType: String
    public var size: Int64
    public var digest: String
    public var annotations: [String: String]?
    public init(mediaType: String, size: Int64, digest: String, annotations: [String: String]? = nil) {
        self.mediaType = mediaType; self.size = size; self.digest = digest; self.annotations = annotations
    }
    public func validate() throws {
        guard OCIReference.validDigest(digest), size >= 0, size <= 2_147_483_648 else { throw UVError("Invalid or oversized OCI descriptor.") }
    }
}
public struct OCIManifest: Codable {
    public var schemaVersion: Int = 2
    public var mediaType: String = "application/vnd.oci.image.manifest.v1+json"
    public var config: OCIDescriptor
    public var layers: [OCIDescriptor]
    public var annotations: [String: String]?
    public init(config: OCIDescriptor, layers: [OCIDescriptor]) { self.config = config; self.layers = layers }
    public func validate() throws {
        guard schemaVersion == 2, mediaType == "application/vnd.oci.image.manifest.v1+json", !layers.isEmpty, layers.count <= 10000 else { throw UVError("Unsupported OCI manifest; expected a VM image manifest.") }
        try config.validate()
        for layer in layers { try layer.validate() }
    }
}
