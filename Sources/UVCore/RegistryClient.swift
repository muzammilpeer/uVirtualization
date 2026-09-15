import Foundation

private final class RegistryRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var request = request
        if response.url?.host != request.url?.host || response.url?.port != request.url?.port {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(request)
    }
}

public actor RegistryClient {
    public let reference: OCIReference
    private var token: String?
    private let session = URLSession(configuration: .ephemeral, delegate: RegistryRedirects(), delegateQueue: nil)
    public init(reference: OCIReference) { self.reference = reference }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/vnd.oci.image.manifest.v1+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }
    private func authenticate(_ response: HTTPURLResponse) async throws {
        guard let header = response.value(forHTTPHeaderField: "WWW-Authenticate"), header.lowercased().hasPrefix("bearer ") else { throw UVError("Registry requires unsupported authentication.") }
        let expression = try NSRegularExpression(pattern: "([a-zA-Z]+)=\"([^\"]*)\"")
        var fields: [String: String] = [:]
        for match in expression.matches(in: header, range: NSRange(header.startIndex..., in: header)) {
            fields[(header as NSString).substring(with: match.range(at: 1))] = (header as NSString).substring(with: match.range(at: 2))
        }
        guard let realm = fields["realm"], var url = URLComponents(string: realm), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw UVError("Invalid registry token endpoint.") }
        url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name: "service", value: fields["service"]), URLQueryItem(name: "scope", value: "repository:\(reference.repository):pull")]
        let (data, response) = try await session.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_048_576,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (json["token"] ?? json["access_token"]) as? String else { throw UVError("Registry authentication failed.") }
        self.token = token
    }
    public func download(_ url: URL) async throws -> URL {
        for attempt in 0..<4 {
            try Task.checkCancellation()
            do {
                let (file, raw) = try await session.download(for: request(url))
                guard let response = raw as? HTTPURLResponse else { throw UVError("Invalid registry response.") }
                if response.statusCode == 401, attempt < 3 {
                    try? FileManager.default.removeItem(at: file)
                    try await authenticate(response)
                    continue
                }
                guard response.statusCode == 200 else {
                    try? FileManager.default.removeItem(at: file)
                    if [429, 500, 502, 503, 504].contains(response.statusCode), attempt < 3 {
                        try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000); continue
                    }
                    throw UVError("Registry request failed (HTTP \(response.statusCode)).")
                }
                return file
            } catch let error as URLError where attempt < 3 && error.code != .cancelled {
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }
        throw UVError("Registry retry limit reached.")
    }
    public func manifest() async throws -> (OCIManifest, String) {
        let file = try await download(reference.url("manifests/" + reference.reference))
        defer { try? FileManager.default.removeItem(at: file) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16_777_216 else { throw UVError("Manifest exceeds size limit.") }
        let data = try Data(contentsOf: file)
        let digest = FileDigest.sha256(data)
        if reference.reference.hasPrefix("sha256:"), digest != reference.reference { throw UVError("Manifest digest mismatch.") }
        let manifest = try JSONDecoder().decode(OCIManifest.self, from: data)
        try manifest.validate()
        return (manifest, digest)
    }
    public func blob(_ descriptor: OCIDescriptor, cache: URL) async throws -> URL {
        try descriptor.validate()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = cache.appendingPathComponent(String(descriptor.digest.dropFirst(7)))
        if FileManager.default.fileExists(atPath: destination.path) {
            try requireRegularFile(destination)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if size == Int(descriptor.size), try FileDigest.sha256(destination) == descriptor.digest { return destination }
            try FileManager.default.removeItem(at: destination)
        }
        let file = try await download(reference.url("blobs/" + descriptor.digest))
        defer { try? FileManager.default.removeItem(at: file) }
        guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(descriptor.size),
              try FileDigest.sha256(file) == descriptor.digest else { throw UVError("Blob size or digest mismatch.") }
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }
}
