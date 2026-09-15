import XCTest
import Compression
@testable import UVCore

final class RegistryTests: XCTestCase {
    func testReferenceParsingRejectsPathsAndCredentials() throws {
        XCTAssertEqual(try OCIReference("ghcr.io/cirruslabs/macos-tahoe-base").reference, "latest")
        XCTAssertEqual(try OCIReference("ghcr.io/a/b:v1").repository, "a/b")
        for bad in ["https://ghcr.io/a", "user@ghcr.io/a", "ghcr.io/../a", "ghcr.io/a?x=1", "ghcr.io/a@sha256:bad", "ghcr.io/a:", "ghcr.io/a//b"] {
            XCTAssertThrowsError(try OCIReference(bad), bad)
        }
    }
    func testTartLayerDecompressionIsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 65, count: 1_048_576)
        let compressed = try (bytes as NSData).compressed(using: .lz4) as Data
        let source = root.appendingPathComponent("layer")
        let destination = root.appendingPathComponent("disk")
        try compressed.write(to: source)
        try SparseDisk.create(at: destination, bytes: 1)
        let digest = try RegistryImages.decompress(source, to: destination, offset: 0, expectedSize: UInt64(bytes.count))
        XCTAssertEqual(digest, FileDigest.sha256(bytes))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertThrowsError(try RegistryImages.decompress(source, to: destination, offset: 0, expectedSize: 10))
    }
    func testDescriptorValidation() {
        XCTAssertThrowsError(try OCIDescriptor(mediaType: "x", size: -1, digest: "../../escape").validate())
        XCTAssertTrue(OCIReference.validDigest(FileDigest.sha256(Data())))
    }
}
