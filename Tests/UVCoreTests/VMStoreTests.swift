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

final class GuestResourceTests: XCTestCase {
    func testLinuxAndMacMinimumsDiffer() throws {
        // A 20 GB registry disk is 19 GiB when rounded up, not 20 GiB.
        XCTAssertNoThrow(try VMConfiguration(name: "ubuntu", diskGiB: 19, guest: "linux"))
        XCTAssertThrowsError(try VMConfiguration(name: "linux", diskGiB: 0, guest: "linux"))
        XCTAssertThrowsError(try VMConfiguration(name: "mac", diskGiB: 19))
        XCTAssertNoThrow(try VMConfiguration(name: "linux", memoryMiB: 1024, guest: "linux"))
        XCTAssertThrowsError(try VMConfiguration(name: "mac", memoryMiB: 1024))
        var model = try VMConfiguration(name: "vm")
        model.macAddress = "not-a-mac"
        XCTAssertThrowsError(try model.validate())
        model.macAddress = nil
        model.minimumCPUCount = -1
        XCTAssertThrowsError(try model.validate())
    }
}

final class StorageSelectionTests: XCTestCase {
    func testSelectingVMFolderOpensItsLibraryAndSelectsVM() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "ci-base"))
        let directory = try store.directory("ci-base")
        try Data([0]).write(to: directory.appendingPathComponent("disk.img"))
        let selection = try VMStore.resolveSelection(directory)
        XCTAssertEqual(selection.store.root.path, store.root.path)
        XCTAssertEqual(selection.vmName, "ci-base")
        XCTAssertEqual(try selection.store.list().map(\.name), ["ci-base"])
        let library = try VMStore.resolveSelection(root)
        XCTAssertNil(library.vmName)
        XCTAssertEqual(library.store.root.path, store.root.path)
    }
    func testLibraryIgnoresOrdinaryFilesButRejectsInvalidVMConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "ci-base"))
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other folder"), withIntermediateDirectories: false)
        XCTAssertEqual(try store.list().map(\.name), ["ci-base"])
        try Data("broken".utf8).write(to: store.directory("ci-base").appendingPathComponent("config.json"))
        XCTAssertThrowsError(try store.list())
        XCTAssertThrowsError(try VMStore.resolveSelection(store.directory("ci-base")))
    }
    func testSelectingSymlinkOrFileIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "ci-base"))
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: store.directory("ci-base"))
        XCTAssertThrowsError(try VMStore.resolveSelection(alias))
        XCTAssertThrowsError(try VMStore.resolveSelection(store.directory("ci-base").appendingPathComponent("config.json")))
    }
}
