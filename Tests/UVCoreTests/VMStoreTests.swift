import XCTest
@testable import UVCore

final class VMStoreTests: XCTestCase {
    func temporaryStore() throws -> VMStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return VMStore(root: root)
    }

    func testRoundTripAndDuplicatePreservesOriginal() throws {
        let store = try temporaryStore()
        let vm = try VMConfiguration(name: "tahoe-base")
        try store.create(vm)
        XCTAssertEqual(try store.load(vm.name), vm)
        XCTAssertThrowsError(try store.create(VMConfiguration(name: vm.name, cpuCount: 8)))
        XCTAssertEqual(try store.load(vm.name), vm)
        XCTAssertEqual(try store.list(), [vm])
    }

    func testUnsafeNamesAndInvalidResources() throws {
        for name in ["", "..", "../escape", "a/b", "/tmp/test", ".hidden", "with space", String(repeating: "x", count: 65)] {
            XCTAssertThrowsError(try VMConfiguration(name: name), name)
        }
        XCTAssertThrowsError(try VMConfiguration(name: "test", cpuCount: 0))
        XCTAssertThrowsError(try VMConfiguration(name: "test", memoryMiB: 1024))
        XCTAssertThrowsError(try VMConfiguration(name: "test", diskGiB: -1))
    }

    func testUnknownSchemaAndNameMismatchRejected() throws {
        let store = try temporaryStore()
        try store.create(VMConfiguration(name: "test"))
        let url = store.root.appendingPathComponent("test/config.json")
        let original = try Data(contentsOf: url)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertThrowsError(try store.load("test"))
        json["schemaVersion"] = 1
        json["name"] = "different"
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertThrowsError(try store.load("test"))
    }

    func testSymlinkRejected() throws {
        let store = try temporaryStore()
        try store.create(VMConfiguration(name: "original"))
        try FileManager.default.createSymbolicLink(at: store.root.appendingPathComponent("alias"),
                                                  withDestinationURL: store.root.appendingPathComponent("original"))
        XCTAssertThrowsError(try store.load("alias"))
        XCTAssertThrowsError(try store.create(VMConfiguration(name: "alias")))
        XCTAssertEqual(try store.load("original").name, "original")
    }

    func testEmptyStoreDoesNotCreateDirectory() throws {
        let store = try temporaryStore()
        XCTAssertEqual(try store.list(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.path))
    }
}
