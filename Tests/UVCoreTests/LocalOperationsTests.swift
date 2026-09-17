import XCTest
@testable import UVCore

final class LocalOperationsTests: XCTestCase {
    func store() throws -> VMStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return VMStore(root: root)
    }
    func testCloneRenameConfigureDelete() throws {
        let store = try store()
        try store.create(VMConfiguration(name: "one"))
        try store.clone("one", to: "two")
        XCTAssertNotNil(try store.load("two").macAddress)
        try store.rename("two", to: "three")
        XCTAssertThrowsError(try store.load("two"))
        try store.configure("three", cpu: 2, disk: 80)
        XCTAssertEqual(try store.load("three").diskGiB, 80)
        XCTAssertThrowsError(try store.configure("three", disk: 40))
        let lock = try store.lock("three")
        XCTAssertThrowsError(try store.delete("three"))
        XCTAssertThrowsError(try store.configure("three", cpu: 3))
        lock.unlock()
        try store.delete("three")
        XCTAssertEqual(try store.list().map(\.name), ["one"])
    }
    func testArchiveRoundTripAndCorruption() throws {
        let store = try store()
        try store.create(VMConfiguration(name: "one"))
        let archive = store.root.appendingPathComponent(".test.uvma")
        try VMArchive.export(store: store, name: "one", to: archive)
        try VMArchive.importVM(store: store, from: archive, name: "two")
        XCTAssertEqual(try store.load("two").name, "two")
        var data = try Data(contentsOf: archive)
        data[data.count - 1] ^= 1
        try data.write(to: archive)
        XCTAssertThrowsError(try VMArchive.importVM(store: store, from: archive, name: "bad"))
        XCTAssertThrowsError(try store.load("bad"))
    }
    func testArchiveTraversalRejected() throws {
        let store = try store()
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        let header = Data("{\"version\":1,\"files\":[{\"name\":\"../escape\",\"size\":1,\"digest\":\"bad\"}]}".utf8)
        var data = Data("UVMARCH1\n\(header.count)\n".utf8)
        data.append(header)
        let archive = store.root.appendingPathComponent(".bad.uvma")
        try data.write(to: archive)
        XCTAssertThrowsError(try VMArchive.importVM(store: store, from: archive, name: "bad"))
    }
}

final class SavedStateSafetyTests: XCTestCase {
    func testSuspendedVMRejectsOfflineMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "vm"))
        let states = root.appendingPathComponent(".states")
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)
        try Data("state".utf8).write(to: states.appendingPathComponent("vm.bin"))
        XCTAssertEqual(try RuntimeControl.status(store: store, name: "vm").state, "suspended")
        XCTAssertThrowsError(try store.configure("vm", cpu: 2))
        XCTAssertThrowsError(try store.clone("vm", to: "other"))
        XCTAssertThrowsError(try store.rename("vm", to: "other"))
        XCTAssertThrowsError(try store.delete("vm"))
    }
}

final class ArtifactCopyTests: XCTestCase {
    func testCloneWritesDoNotAlterSourceAndCannotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("copy")
        try Data("original".utf8).write(to: source)
        try copyArtifact(from: source, to: destination)
        try Data("changed".utf8).write(to: destination)
        XCTAssertEqual(try String(contentsOf: source), "original")
        XCTAssertThrowsError(try copyArtifact(from: source, to: destination))
        XCTAssertEqual(try String(contentsOf: destination), "changed")
    }
}
