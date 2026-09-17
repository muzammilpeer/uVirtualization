import XCTest
@testable import UVCore

private final class MockRegistryProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "registry.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class RegistryTransportTests: XCTestCase {
    func testChunkedUploadAndCommitDigest() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file); MockRegistryProtocol.handler = nil }
        let payload = Data(repeating: 42, count: 10000)
        try payload.write(to: file)
        let expected = FileDigest.sha256(payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRegistryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let lock = NSLock()
        var methods: [String] = []
        MockRegistryProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            let method = request.httpMethod!
            methods.append(method)
            switch method {
            case "HEAD": return (404, [:], Data())
            case "POST": return (202, ["Location": "/v2/team/vm/blobs/uploads/session"], Data())
            case "PATCH":
                return (202, ["Location": "/v2/team/vm/blobs/uploads/session", "Range": "0-9999"], Data())
            case "PUT":
                XCTAssertTrue(request.url!.absoluteString.contains(expected))
                return (201, [:], Data())
            default: throw UVError("Unexpected HTTP method")
            }
        }
        let client = RegistryClient(reference: try OCIReference("registry.invalid/team/vm:test"), pushAccess: true, session: session)
        let descriptor = try await client.pushBlob(file, mediaType: "application/vnd.uvirtualization.disk.v1")
        XCTAssertEqual(descriptor.digest, expected)
        XCTAssertEqual(descriptor.size, 10000)
        XCTAssertEqual(methods, ["HEAD", "POST", "PATCH", "PUT"])
    }
    func testUploadRejectsCrossOriginLocation() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file); MockRegistryProtocol.handler = nil }
        try Data([1]).write(to: file)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRegistryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        MockRegistryProtocol.handler = { request in
            request.httpMethod == "HEAD" ? (404, [:], Data()) : (202, ["Location": "https://untrusted.invalid/upload"], Data())
        }
        let client = RegistryClient(reference: try OCIReference("registry.invalid/team/vm:test"), pushAccess: true, session: session)
        do { _ = try await client.pushBlob(file, mediaType: "x"); XCTFail("Expected rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("cross-origin")) }
    }
}
