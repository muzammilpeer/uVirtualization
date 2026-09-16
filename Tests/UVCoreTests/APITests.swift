import XCTest
@testable import UVCore

final class APITests: XCTestCase {
    func testAuthenticatedRequest() throws {
        let request = try APIRequest.parse(Data("GET /v1/vms HTTP/1.1\r\nAuthorization: Bearer secret\r\nHost: localhost\r\n\r\n".utf8))
        XCTAssertTrue(request.authorized(token: "secret"))
        XCTAssertFalse(request.authorized(token: "wrong"))
        XCTAssertEqual(request.path, "/v1/vms")
    }
    func testRejectsSmugglingAndOversizeRequests() {
        for request in [
            "GET /v1/vms HTTP/1.1\r\nAuthorization: a\r\nAuthorization: b\r\n\r\n",
            "POST /v1/vms/x/start HTTP/1.1\r\nContent-Length: 1\r\n\r\nx",
            "POST /v1/vms/x/start HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "GET /v1/%2e%2e HTTP/1.1\r\n\r\n",
            String(repeating: "x", count: 17000)
        ] { XCTAssertThrowsError(try APIRequest.parse(Data(request.utf8))) }
    }
}

final class APITokenTests: XCTestCase {
    @MainActor func testPrivateTokenAcceptedAndWorldReadableRejected() throws {
        let token = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: token) }
        try Data(String(repeating: "a", count: 64).utf8).write(to: token)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: token.path)
        XCTAssertEqual(try ControlAPIServer.readToken(from: token), String(repeating: "a", count: 64))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: token.path)
        XCTAssertThrowsError(try ControlAPIServer.readToken(from: token)) { error in
            XCTAssertTrue(error.localizedDescription.contains("private"))
        }
    }
}
