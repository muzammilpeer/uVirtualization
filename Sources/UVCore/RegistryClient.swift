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
    private let pushAccess: Bool
    private let session: URLSession
    public init(reference: OCIReference, pushAccess: Bool = false, session: URLSession? = nil) {
        self.reference = reference; self.pushAccess = pushAccess
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: RegistryRedirects(), delegateQueue: nil)
    }

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
        url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name: "service", value: fields["service"]), URLQueryItem(name: "scope", value: "repository:\(reference.repository):\(pushAccess ? "pull,push" : "pull")")]
        var tokenRequest = URLRequest(url: url.url!)
        tokenRequest.timeoutInterval = 60
        // Never send a password to an arbitrary authentication realm.
        if url.host == URL(string: "https://" + reference.host)?.host,
           let credential = try RegistryCredentials.load(host: reference.host) {
            let basic = Data((credential.username + ":" + credential.password).utf8).base64EncodedString()
            tokenRequest.setValue("Basic " + basic, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: tokenRequest)
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
    func send(_ url: URL, method: String, body: Data? = nil, contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<2 {
            var request = request(url, method: method)
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            let (data, raw) = try await session.data(for: request)
            guard let response = raw as? HTTPURLResponse else { throw UVError("Invalid registry response.") }
            if response.statusCode == 401 && attempt == 0 { try await authenticate(response); continue }
            return (data, response)
        }
        throw UVError("Registry authentication failed.")
    }
    private func uploadLocation(_ response: HTTPURLResponse, fallback: URL) throws -> URL {
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: fallback)?.absoluteURL,
              url.scheme == "https", url.host == fallback.host, url.port == fallback.port,
              url.user == nil, url.password == nil else { throw UVError("Invalid or cross-origin registry upload endpoint.") }
        return url
    }
    public func pushBlob(_ file: URL, mediaType: String, annotations: [String: String]? = nil) async throws -> OCIDescriptor {
        let digest = try FileDigest.sha256(file)
        let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let descriptor = OCIDescriptor(mediaType: mediaType, size: size, digest: digest, annotations: annotations)
        try descriptor.validate()
        let (_, exists) = try await send(reference.url("blobs/" + digest), method: "HEAD")
        if exists.statusCode == 200 { return descriptor }
        guard exists.statusCode == 404 else { throw UVError("Blob existence check failed (HTTP \(exists.statusCode)).") }
        let endpoint = reference.url("blobs/uploads/")
        let (_, started) = try await send(endpoint, method: "POST", body: Data())
        guard started.statusCode == 202 else { throw UVError("Cannot start upload (HTTP \(started.statusCode)).") }
        var location = try uploadLocation(started, fallback: endpoint)
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var offset: Int64 = 0
        var failures = 0
        while offset < size {
            try Task.checkCancellation()
            try input.seek(toOffset: UInt64(offset))
            let data = try input.read(upToCount: Int(min(8_388_608, size - offset))) ?? Data()
            guard !data.isEmpty else { throw UVError("Upload source was truncated.") }
            do {
                let (_, response) = try await send(location, method: "PATCH", body: data, contentType: "application/octet-stream")
                guard response.statusCode == 202 else { throw UVError("Upload chunk failed (HTTP \(response.statusCode)).") }
                location = try uploadLocation(response, fallback: location)
                offset += Int64(data.count)
                failures = 0
            } catch {
                failures += 1
                guard failures <= 3 else { throw error }
                try await Task.sleep(nanoseconds: UInt64(failures) * 1_000_000_000)
                let (_, state) = try await send(location, method: "GET")
                guard state.statusCode == 204,
                      let endText = state.value(forHTTPHeaderField: "Range")?.split(separator: "-").last,
                      let end = Int64(endText), end >= 0, end < size else { throw error }
                offset = end + 1
                if state.value(forHTTPHeaderField: "Location") != nil { location = try uploadLocation(state, fallback: location) }
            }
        }
        var final = URLComponents(url: location, resolvingAgainstBaseURL: true)!
        final.queryItems = (final.queryItems ?? []) + [URLQueryItem(name: "digest", value: digest)]
        let (_, committed) = try await send(final.url!, method: "PUT", body: Data(), contentType: "application/octet-stream")
        guard committed.statusCode == 201 else { throw UVError("Blob commit failed (HTTP \(committed.statusCode)).") }
        return descriptor
    }
    public func pushManifest(_ manifest: OCIManifest) async throws {
        guard !reference.reference.hasPrefix("sha256:") else { throw UVError("Push requires a tag.") }
        let data = try JSONEncoder().encode(manifest)
        let (_, response) = try await send(reference.url("manifests/" + reference.reference), method: "PUT", body: data, contentType: manifest.mediaType)
        guard response.statusCode == 201 else { throw UVError("Manifest push failed (HTTP \(response.statusCode)).") }
    }

}
