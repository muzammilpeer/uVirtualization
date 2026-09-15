import XCTest
@testable import UVCore

final class NetworkingTests: XCTestCase {
    func testLeaseMatchingAndExpiry() {
        let leases = """
        {
        hw_address=1,a:b:c:d:e:f
        ip_address=192.168.64.2
        lease=0xffffffff
        }
        {
        hw_address=1,a:b:c:d:e:f
        ip_address=192.168.64.3
        lease=0x1
        }
        """
        XCTAssertEqual(IPDiscovery.address(in: leases, mac: "0a:0b:0c:0d:0e:0f"), "192.168.64.2")
        XCTAssertNil(IPDiscovery.address(in: leases, mac: "00:00:00:00:00:00"))
    }
    func testShareDefaultsToReadOnly() throws {
        let path = FileManager.default.temporaryDirectory.path
        XCTAssertTrue(try DirectoryMount("source=\(path)").readOnly)
        XCTAssertFalse(try DirectoryMount("source=\(path):rw").readOnly)
        XCTAssertThrowsError(try DirectoryMount("../bad=\(path)"))
        XCTAssertThrowsError(try DirectoryMount("invalid"))
    }
}
